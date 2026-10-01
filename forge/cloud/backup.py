#!/usr/bin/env python3
"""Cloud preemption backup runner for ephemeral Spot Dev VM instances.

Executed during instance ACPI shutdown.
Standard-library Python 3 only (zero 3rd party dependencies).
"""


from __future__ import annotations

from datetime import datetime, timezone
import os
from pathlib import Path
import subprocess

SCAN_ROOTS = (Path("/workspace"), Path("/home/mohds"))
LOG_PATH = Path("/var/log/forge-backup.log")


def main() -> None:
    """Scan repositories and push backup branches for dirty working trees."""
    _setup_logging()
    _log("Preemption shutdown hook triggered. Scanning repositories for uncommitted work...")

    token = _fetch_github_token()
    git_repos = _find_git_repositories(SCAN_ROOTS)

    if not git_repos:
        _log("No git repositories found.")
        return

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup_branch = f"spot-backup-{timestamp}"

    for repo_dir in git_repos:
        if _is_dirty(repo_dir):
            _backup_repo(repo_dir, backup_branch, token)

    _log("Shutdown backup sequence completed.")


def _log(message: str) -> None:
    """Log to console and file (gracefully fallback if non-root)."""
    print(f"[Backup] {message}", flush=True)
    try:
        with LOG_PATH.open("a", encoding="utf-8") as handle:
            handle.write(f"[Backup] {message}\n")
    except OSError:
        pass


def _setup_logging() -> None:
    """Ensure log directory exists (ignore permission errors if non-root)."""
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    except OSError:
        pass



def _find_git_repositories(roots: tuple[Path, ...]) -> list[Path]:
    """Find all top-level repository roots containing .git directories."""
    repos: list[Path] = []
    for root in roots:
        if not root.exists():
            continue
        for child in root.iterdir():
            if child.is_dir() and (child / ".git").is_dir():
                repos.append(child)
    return repos


def _is_dirty(repo_dir: Path) -> bool:
    """Check if repository has uncommitted changes or untracked files."""
    proc = subprocess.run(
        ["git", "-C", str(repo_dir), "status", "--porcelain"],
        capture_output=True,
        text=True,
        check=False,
    )
    return bool(proc.stdout.strip())


def _backup_repo(repo_dir: Path, branch_name: str, token: str) -> None:
    """Commit dirty state and push to the backup branch."""
    _log(f"Backing up dirty repository: {repo_dir.name} -> branch {branch_name}")

    # Set user info if not configured
    subprocess.run(["git", "-C", str(repo_dir), "config", "user.name", "Forge Auto Backup"], check=False)
    subprocess.run(["git", "-C", str(repo_dir), "config", "user.email", "forge-backup@localhost"], check=False)

    # Checkout new branch and commit everything
    subprocess.run(["git", "-C", str(repo_dir), "checkout", "-b", branch_name], check=False)
    subprocess.run(["git", "-C", str(repo_dir), "add", "-A"], check=False)
    subprocess.run(
        ["git", "-C", str(repo_dir), "commit", "-m", f"Automatic backup before Spot preemption ({branch_name})"],
        check=False,
    )

    # Push with token authentication
    remote_url = _get_remote_url(repo_dir)
    push_url = _build_authenticated_url(remote_url, token)

    _log(f"Pushing {branch_name} to remote...")
    proc = subprocess.run(
        ["git", "-C", str(repo_dir), "push", push_url, f"{branch_name}:{branch_name}"],
        capture_output=True,
        text=True,
        check=False,
    )

    if proc.returncode == 0:
        _log(f"Successfully pushed backup branch: {branch_name}")
    else:
        _log(f"Push failed for {repo_dir.name}: {proc.stderr.strip()}")


def _get_remote_url(repo_dir: Path) -> str:
    """Get remote origin URL for repository."""
    proc = subprocess.run(
        ["git", "-C", str(repo_dir), "remote", "get-url", "origin"],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.stdout.strip()


def _build_authenticated_url(clone_url: str, token: str) -> str:
    """Inject OAuth token into HTTPS GitHub URL for authenticated pushing."""
    if not token or not clone_url.startswith("https://github.com/"):
        return clone_url
    return clone_url.replace("https://github.com/", f"https://oauth2:{token}@github.com/")


def _fetch_github_token() -> str:
    """Fetch GitHub token from GCP Secret Manager via gcloud CLI."""
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
    except subprocess.CalledProcessError:
        return ""


if __name__ == "__main__":
    main()
