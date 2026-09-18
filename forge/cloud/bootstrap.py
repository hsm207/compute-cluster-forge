#!/usr/bin/env python3
"""Cloud bootstrap runner for ephemeral Spot Dev VM instances.

Executed inside the cloud VM during instance startup.
Standard-library Python 3 only (zero 3rd party dependencies).
"""


from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import urllib.request
import urllib.error

METADATA_BASE = "http://metadata.google.internal/computeMetadata/v1/instance"
WORKSPACE_DIR = Path("/workspace")
LOG_PATH = Path("/var/log/forge-bootstrap.log")


def main() -> None:
    """Orchestrate VM bootstrap stages in strict sequence."""
    _setup_logging()
    _log("Starting Forge cloud bootstrap runner...")

    _install_base_toolchain()
    token = _fetch_github_token()
    _configure_system_auth(token)
    manifest = _fetch_workspace_manifest()

    if manifest:
        _provision_workspace(manifest, token)
    else:
        _log("No workspace manifest provided; skipping repository cloning.")

    _configure_permissions()
    _log("Forge cloud bootstrap completed successfully.")


def _log(message: str) -> None:
    """Append message to system bootstrap log and stdout."""
    print(f"[Forge] {message}", flush=True)
    with LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(f"[Forge] {message}\n")


def _setup_logging() -> None:
    """Ensure log directory exists."""
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)


def _install_base_toolchain() -> None:
    """Install core build packages, Node.js LTS, GitHub CLI, and freebuff."""
    _log("Installing base system packages...")
    os.environ["DEBIAN_FRONTEND"] = "noninteractive"
    _run_cmd(["apt-get", "update", "-y"])
    _run_cmd(["apt-get", "install", "-y", "curl", "git", "ca-certificates", "gnupg", "jq"])

    # Configure NodeSource repository for Node.js 20.x
    keyring_dir = Path("/etc/apt/keyrings")
    keyring_dir.mkdir(parents=True, exist_ok=True)

    gpg_key_path = keyring_dir / "nodesource.gpg"
    if not gpg_key_path.exists():
        _run_shell(
            "curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | "
            "gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg"
        )
        sources_list = Path("/etc/apt/sources.list.d/nodesource.list")
        sources_list.write_text(
            "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] "
            "https://deb.nodesource.com/node_20.x nodistro main\n"
        )
        _run_cmd(["apt-get", "update", "-y"])

    _run_cmd(["apt-get", "install", "-y", "nodejs", "gh"])
    _run_cmd(["npm", "install", "-g", "freebuff"])


def _fetch_github_token() -> str:
    """Fetch GitHub token from GCP Secret Manager via gcloud CLI."""
    _log("Fetching GitHub authentication token from Secret Manager...")
    try:
        proc = subprocess.run(
            [
                "gcloud",
                "secrets",
                "versions",
                "access",
                "latest",
                "--secret=github-token",
                "--project=compute-cluster-492317",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        return proc.stdout.strip()
    except subprocess.CalledProcessError as exc:
        _log(f"Warning: Failed to fetch github-token from Secret Manager: {exc.stderr}")
        return ""


def _configure_system_auth(token: str) -> None:
    """Inject persistent GH_TOKEN into profile scripts."""
    if not token:
        return

    _log("Configuring shell authentication environment...")
    profile_script = Path("/etc/profile.d/github_auth.sh")
    profile_script.write_text(
        f'export GH_TOKEN="{token}"\n'
        f'export GITHUB_TOKEN="{token}"\n'
    )
    profile_script.chmod(0o755)

    bashrc = Path("/etc/bash.bashrc")
    with bashrc.open("a", encoding="utf-8") as handle:
        handle.write(
            f'\nif [ -z "${{GH_TOKEN:-}}" ]; then\n'
            f'  export GH_TOKEN="{token}"\n'
            f'  export GITHUB_TOKEN="{token}"\n'
            f'fi\n'
        )


def _fetch_workspace_manifest() -> dict | None:
    """Fetch workspace JSON manifest from instance metadata."""
    _log("Reading workspace manifest from instance metadata...")
    url = f"{METADATA_BASE}/attributes/workspace-manifest"
    req = urllib.request.Request(url, headers={"Metadata-Flavor": "Google"})

    try:
        with urllib.request.urlopen(req) as resp:
            content = resp.read().decode("utf-8")
            return json.loads(content)
    except urllib.error.URLError:
        _log("No workspace-manifest attribute present.")
        return None
    except json.JSONDecodeError as exc:
        _log(f"Invalid JSON in workspace-manifest attribute: {exc}")
        return None


def _provision_workspace(manifest: dict, token: str) -> None:
    """Clone repositories and write remote VS Code workspace file."""
    workspace_name = manifest.get("name", "dev")
    repositories = manifest.get("repositories", [])
    _log(f"Provisioning workspace '{workspace_name}' with {len(repositories)} repositories...")

    WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)

    for repo_info in repositories:
        name = repo_info.get("name", "")
        clone_url = repo_info.get("clone_url", "")
        if not name or not clone_url:
            continue

        target_dir = WORKSPACE_DIR / name
        if target_dir.exists():
            _log(f"Repository directory already exists: {target_dir}")
            continue

        _log(f"Cloning {name} from {clone_url}...")
        authenticated_url = _build_authenticated_url(clone_url, token)
        _run_cmd(["git", "clone", authenticated_url, str(target_dir)])

        # Sanitize remote origin on disk so token is never stored
        _run_cmd(["git", "-C", str(target_dir), "remote", "set-url", "origin", clone_url])

    # Write remote .code-workspace file
    remote_ws_file = WORKSPACE_DIR / f"{workspace_name}.code-workspace"
    ws_data = {
        "folders": [
            {"name": r.get("name"), "path": f"./{r.get('name')}"}
            for r in repositories
        ],
        "settings": {},
    }
    remote_ws_file.write_text(json.dumps(ws_data, indent=2), encoding="utf-8")
    _log(f"Generated remote workspace file: {remote_ws_file}")


def _build_authenticated_url(clone_url: str, token: str) -> str:
    """Inject OAuth token into HTTPS GitHub URL for authenticated cloning."""
    if not token or not clone_url.startswith("https://github.com/"):
        return clone_url
    return clone_url.replace("https://github.com/", f"https://oauth2:{token}@github.com/")


def _configure_permissions() -> None:
    """Set workspace ownership and Git safe directories."""
    _log("Configuring workspace permissions and Git safety...")
    _run_cmd(["git", "config", "--system", "--add", "safe.directory", "*"])

    # mohds is the standard user created by OS Login / compute engine
    target_user = "mohds"
    _run_shell(
        f"if id '{target_user}' &>/dev/null; then "
        f"  chown -R {target_user}:{target_user} /workspace; "
        f"else "
        f"  chmod -R 777 /workspace; "
        f"fi"
    )


def _run_cmd(cmd: list[str]) -> None:
    """Execute a command without raising if non-critical."""
    subprocess.run(cmd, check=False)


def _run_shell(cmd_str: str) -> None:
    """Execute a shell pipeline command."""
    subprocess.run(cmd_str, shell=True, check=False, executable="/bin/bash")


if __name__ == "__main__":
    main()
