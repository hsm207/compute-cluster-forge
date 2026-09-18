"""Humble object adapter for Google Cloud Platform compute commands."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import shutil
import subprocess
import sys


@dataclass(frozen=True)
class MigLaunchConfig:
    """Domain parameter object bundling configuration for MIG deployment."""

    project: str
    region: str
    template_name: str
    mig_name: str
    machine_type: str
    manifest_path: Path
    bootstrap_script: Path
    backup_script: Path


class GCloudAdapterError(Exception):
    """Raised when a gcloud command fails."""


def deploy_regional_mig(config: MigLaunchConfig) -> str:
    """Create versioned instance template and update the Regional MIG to use it."""
    versioned_template = _create_versioned_template(config)
    _update_or_create_mig(config, versioned_template)
    return versioned_template


def _get_gcloud_binary() -> str:
    """Resolve cross-platform gcloud executable name."""
    if sys.platform == "win32":
        resolved = shutil.which("gcloud.cmd") or shutil.which("gcloud")
        return resolved or "gcloud.cmd"
    return "gcloud"


def _create_versioned_template(config: MigLaunchConfig) -> str:
    """Create a new timestamp-versioned instance template with updated manifest."""
    gcloud = _get_gcloud_binary()
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    versioned_name = f"{config.template_name}-{timestamp}"

    cmd = [
        gcloud, "compute", "instance-templates", "create", versioned_name,
        "--project", config.project,
        "--region", config.region,
        "--machine-type", config.machine_type,
        "--provisioning-model", "SPOT",
        "--instance-termination-action", "STOP",
        "--labels", "project=dev-spot-box,environment=dev",
        "--scopes", "https://www.googleapis.com/auth/cloud-platform",
        "--image-family", "debian-12",
        "--image-project", "debian-cloud",
        "--boot-disk-size", "10GB",
        "--boot-disk-type", "pd-standard",
        "--boot-disk-auto-delete",
        f"--metadata-from-file=startup-script={config.bootstrap_script},shutdown-script={config.backup_script},workspace-manifest={config.manifest_path}",
    ]

    _execute_gcloud(cmd, f"Failed to create instance template {versioned_name}")
    return versioned_name


def _update_or_create_mig(config: MigLaunchConfig, template_name: str) -> None:
    """Ensure the Regional Managed Instance Group uses the specified template."""
    gcloud = _get_gcloud_binary()

    check_proc = subprocess.run(
        [
            gcloud, "compute", "instance-groups", "managed", "describe", config.mig_name,
            "--region", config.region,
            "--project", config.project,
            "--format", "value(name)",
        ],
        capture_output=True,
        text=True,
        check=False,
    )

    if check_proc.returncode == 0 and check_proc.stdout.strip() == config.mig_name:
        # Set new template on existing MIG and trigger rollout replacement
        set_template_cmd = [
            gcloud, "compute", "instance-groups", "managed", "set-instance-template", config.mig_name,
            "--template", template_name,
            "--region", config.region,
            "--project", config.project,
        ]
        _execute_gcloud(set_template_cmd, "Failed to update MIG instance template")

        # In regional MIGs with 3 zones, fixed max-surge must be at least equal to zone count (3)
        replace_cmd = [
            gcloud, "compute", "instance-groups", "managed", "rolling-action", "replace", config.mig_name,
            "--region", config.region,
            "--project", config.project,
            "--max-surge", "3",
            "--max-unavailable", "0",
        ]
        _execute_gcloud(replace_cmd, "Failed to rolling-replace instances in MIG")
    else:
        # Create fresh MIG
        create_cmd = [
            gcloud, "compute", "instance-groups", "managed", "create", config.mig_name,
            "--project", config.project,
            "--region", config.region,
            "--template", template_name,
            "--size", "1",
            "--base-instance-name", "dev-box",
            "--target-distribution-shape", "ANY",
        ]
        _execute_gcloud(create_cmd, "Failed to create Managed Instance Group")


def _execute_gcloud(cmd: list[str], error_prefix: str) -> None:
    """Execute a gcloud command, raising a clean GCloudAdapterError on failure."""
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as exc:
        msg = exc.stderr.strip() if exc.stderr else exc.stdout.strip()
        raise GCloudAdapterError(f"{error_prefix}: {msg}") from exc
