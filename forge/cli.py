"""Command line interface entrypoint for forge."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from forge.domain.workspace import build_workspace_manifest
from forge.adapters.git import get_origin_url, get_git_author_identity
from forge.adapters.gcloud import (
    deploy_regional_mig,
    MigLaunchConfig,
    teardown_regional_mig,
    list_dev_migs,
    delete_all_dev_spot_templates,
)

DEFAULT_WORKSPACES_DIR = Path("C:/Users/mohds/Documents/GitHub/_workspaces")
DEFAULT_PROJECT = "compute-cluster-492317"
DEFAULT_REGION = "us-west1"


def main(argv: list[str] | None = None) -> int:
    """Parse arguments and execute the requested forge command."""
    parser = _create_parser()
    args = parser.parse_args(argv)

    if args.command == "launch":
        return _handle_launch(args)
    if args.command in ("teardown", "stop", "down"):
        return _handle_teardown(args)

    parser.print_help()
    return 1


def _create_parser() -> argparse.ArgumentParser:
    """Construct command-line argument parser."""
    parser = argparse.ArgumentParser(
        prog="forge",
        description="Zero-trust ephemeral dev cluster manager with multi-repo workspace ingestion.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    launch_parser = subparsers.add_parser("launch", help="Launch a multi-repo VS Code workspace on GCP.")
    launch_parser.add_argument(
        "workspace",
        help="Name of the workspace (e.g. 'freebuff') or full path to .code-workspace file.",
    )
    launch_parser.add_argument(
        "--region",
        default=DEFAULT_REGION,
        help=f"GCP region (default: {DEFAULT_REGION}).",
    )
    launch_parser.add_argument(
        "--machine-type",
        default="e2-highmem-2",
        help="GCP machine type (default: e2-highmem-2).",
    )

    teardown_parser = subparsers.add_parser(
        "teardown",
        aliases=["stop", "down"],
        help="Teardown and destroy active ephemeral dev clusters on GCP.",
    )
    teardown_parser.add_argument(
        "--region",
        default=None,
        help="Specific GCP region to teardown. If omitted, scans across all regions.",
    )
    teardown_parser.add_argument(
        "--all",
        action="store_true",
        help="Teardown all dev-box clusters and purge all leftover dev-spot templates.",
    )
    teardown_parser.add_argument(
        "--keep-templates",
        action="store_true",
        help="Do not delete associated instance templates during teardown.",
    )
    return parser


def _handle_launch(args: argparse.Namespace) -> int:
    """Resolve workspace, generate manifest, and trigger MIG deployment."""
    workspace_file = _resolve_workspace_file(args.workspace)
    print(f"[Forge] Reading workspace: {workspace_file}")

    user_name, user_email = get_git_author_identity()
    if user_name or user_email:
        print(f"[Forge] Resolved Git author identity: {user_name} <{user_email}>")

    manifest = build_workspace_manifest(
        workspace_file,
        resolve_remote=get_origin_url,
        git_user_name=user_name,
        git_user_email=user_email,
    )
    print(f"[Forge] Resolved {len(manifest.repositories)} member repositories:")
    for repo in manifest.repositories:
        print(f"  - {repo.name}: {repo.clone_url}")

    # Write manifest to temporary scratch location
    scratch_dir = Path("scratch")
    scratch_dir.mkdir(parents=True, exist_ok=True)
    manifest_file = scratch_dir / f"{manifest.name}-manifest.json"
    manifest_file.write_text(json.dumps(manifest.to_dict(), indent=2), encoding="utf-8")

    bootstrap_script = Path(__file__).parent / "cloud" / "bootstrap.py"
    backup_script = Path(__file__).parent / "cloud" / "backup.py"

    config = MigLaunchConfig(
        project=DEFAULT_PROJECT,
        region=args.region,
        template_name="dev-spot-template",
        mig_name="dev-box-mig",
        machine_type=args.machine_type,
        manifest_path=manifest_file.resolve(),
        bootstrap_script=bootstrap_script.resolve(),
        backup_script=backup_script.resolve(),
    )

    print(f"[Forge] Deploying Regional MIG ({config.mig_name}) in {config.region}...")
    deploy_regional_mig(config)
    print(f"[Forge] Deployment initiated successfully!")
    print(f"[Forge] Once the VM is ready, connect via VS Code: Remote-SSH -> dev-box")
    print(f"[Forge] Then open: /workspace/{manifest.name}.code-workspace")
    return 0


def _handle_teardown(args: argparse.Namespace) -> int:
    """Tear down active dev clusters, MIGs, and templates."""
    delete_templates = not args.keep_templates

    if args.region:
        print(f"[Forge] Tearing down dev-box-mig in region {args.region}...")
        deleted_templates = teardown_regional_mig(
            mig_name="dev-box-mig",
            region=args.region,
            project=DEFAULT_PROJECT,
            delete_templates=delete_templates,
        )
        print(f"[Forge] Destroyed dev-box-mig in {args.region}.")
        if deleted_templates:
            print(f"[Forge] Purged {len(deleted_templates)} associated template(s): {', '.join(deleted_templates)}")
        return 0

    print("[Forge] Discovering active dev-box clusters across all regions...")
    migs = list_dev_migs(mig_name="dev-box-mig", project=DEFAULT_PROJECT)

    if not migs:
        print("[Forge] No active dev-box Managed Instance Groups found.")
    else:
        for mig in migs:
            r = mig["region"]
            print(f"[Forge] Tearing down {mig['name']} in region {r} (current size: {mig.get('size', 'unknown')})...")
            deleted_templates = teardown_regional_mig(
                mig_name=mig["name"],
                region=r,
                project=DEFAULT_PROJECT,
                delete_templates=delete_templates,
            )
            print(f"[Forge] Destroyed {mig['name']} in {r}.")
            if deleted_templates:
                print(f"[Forge] Purged {len(deleted_templates)} associated template(s): {', '.join(deleted_templates)}")

    if args.all and delete_templates:
        print("[Forge] Purging any leftover dev-spot instance templates...")
        purged = delete_all_dev_spot_templates(project=DEFAULT_PROJECT)
        if purged:
            print(f"[Forge] Cleaned up {len(purged)} leftover template(s): {', '.join(purged)}")

    print("[Forge] Teardown complete. All compute clusters destroyed.")
    return 0


def _resolve_workspace_file(name_or_path: str) -> Path:
    """Find the .code-workspace file from a name or explicit path."""
    candidate = Path(name_or_path)
    if candidate.exists() and candidate.is_file():
        return candidate.resolve()

    # Search in default workspaces directory
    named_file = DEFAULT_WORKSPACES_DIR / f"{name_or_path}.code-workspace"
    if named_file.exists():
        return named_file.resolve()

    named_file_raw = DEFAULT_WORKSPACES_DIR / name_or_path
    if named_file_raw.exists():
        return named_file_raw.resolve()

    raise FileNotFoundError(f"Could not find workspace file for '{name_or_path}' in {DEFAULT_WORKSPACES_DIR}")


if __name__ == "__main__":
    sys.exit(main())
