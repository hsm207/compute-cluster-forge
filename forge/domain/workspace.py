"""Domain models and pure logic for VS Code workspace resolution."""

from __future__ import annotations

from dataclasses import dataclass, field
import json
from pathlib import Path
from typing import Callable, Sequence


@dataclass(frozen=True)
class RepoTarget:
    """Represents a single repository within a multi-repo workspace."""

    name: str
    clone_url: str
    relative_path: str


@dataclass(frozen=True)
class WorkspaceManifest:
    """Represents a resolved multi-repo workspace ready for cloud deployment."""

    name: str
    repositories: tuple[RepoTarget, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict:
        """Serialize the manifest to a clean JSON-compatible dictionary."""
        return {
            "name": self.name,
            "repositories": [
                {
                    "name": repo.name,
                    "clone_url": repo.clone_url,
                    "relative_path": repo.relative_path,
                }
                for repo in self.repositories
            ],
        }

    def to_remote_code_workspace_json(self) -> str:
        """Generate the content of a remote VS Code .code-workspace file."""
        content = {
            "folders": [
                {"name": repo.name, "path": repo.relative_path}
                for repo in self.repositories
            ],
            "settings": {},
        }
        return json.dumps(content, indent=2)


RemoteResolver = Callable[[Path], str]


def build_workspace_manifest(
    workspace_path: Path,
    resolve_remote: RemoteResolver,
) -> WorkspaceManifest:
    """Parse a .code-workspace file and resolve each member repo's remote URL.

    Args:
        workspace_path: Path to the local .code-workspace JSON file.
        resolve_remote: Injected function to lookup a repository's remote URL.

    Returns:
        A populated WorkspaceManifest domain entity.
    """
    workspace_dir = workspace_path.parent
    workspace_name = _extract_workspace_name(workspace_path)
    raw_data = _load_workspace_json(workspace_path)

    targets = _resolve_folder_targets(
        raw_folders=raw_data.get("folders", []),
        workspace_dir=workspace_dir,
        resolve_remote=resolve_remote,
    )

    return WorkspaceManifest(name=workspace_name, repositories=tuple(targets))


def _extract_workspace_name(workspace_path: Path) -> str:
    """Extract clean workspace name from filename, removing .code-workspace."""
    filename = workspace_path.name
    if filename.endswith(".code-workspace"):
        return filename[: -len(".code-workspace")]
    return workspace_path.stem


def _load_workspace_json(workspace_path: Path) -> dict:
    """Load and parse the JSON content of a workspace file."""
    with workspace_path.open("r", encoding="utf-8") as file_handle:
        return json.load(file_handle)


def _resolve_folder_targets(
    raw_folders: Sequence[dict],
    workspace_dir: Path,
    resolve_remote: RemoteResolver,
) -> list[RepoTarget]:
    """Resolve each folder entry in a workspace into a RepoTarget."""
    targets: list[RepoTarget] = []

    for item in raw_folders:
        folder_rel_path = item.get("path", "")
        folder_name = item.get("name", "")

        local_repo_dir = (workspace_dir / folder_rel_path).resolve()
        effective_name = folder_name or local_repo_dir.name
        clone_url = resolve_remote(local_repo_dir)

        targets.append(
            RepoTarget(
                name=effective_name,
                clone_url=clone_url,
                relative_path=f"./{effective_name}",
            )
        )

    return targets
