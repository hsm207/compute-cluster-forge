"""Naked unit tests for workspace domain logic."""

import json
from pathlib import Path
import tempfile
import pytest

from forge.domain.workspace import (
    RepoTarget,
    WorkspaceManifest,
    build_workspace_manifest,
)


def test_workspace_manifest_serialization() -> None:
    manifest = WorkspaceManifest(
        name="test-ws",
        repositories=(
            RepoTarget(name="repo-a", clone_url="https://github.com/org/repo-a.git", relative_path="./repo-a"),
            RepoTarget(name="repo-b", clone_url="https://github.com/org/repo-b.git", relative_path="./repo-b"),
        ),
    )

    data = manifest.to_dict()
    assert data["name"] == "test-ws"
    assert len(data["repositories"]) == 2
    assert data["repositories"][0]["name"] == "repo-a"

    remote_json = manifest.to_remote_code_workspace_json()
    parsed = json.loads(remote_json)
    assert len(parsed["folders"]) == 2
    assert parsed["folders"][0]["path"] == "./repo-a"


def test_build_workspace_manifest_from_file() -> None:
    ws_content = {
        "folders": [
            {"name": "custom-name-a", "path": "../folder-a"},
            {"path": "../folder-b"},
        ],
        "settings": {},
    }

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        ws_file = tmp_path / "sample.code-workspace"
        ws_file.write_text(json.dumps(ws_content), encoding="utf-8")

        mock_remotes = {
            "folder-a": "https://github.com/example/folder-a.git",
            "folder-b": "https://github.com/example/folder-b.git",
        }

        def mock_resolver(repo_dir: Path) -> str:
            return mock_remotes.get(repo_dir.name, "https://github.com/unknown.git")

        manifest = build_workspace_manifest(ws_file, resolve_remote=mock_resolver)

        assert manifest.name == "sample"
        assert len(manifest.repositories) == 2
        assert manifest.repositories[0].name == "custom-name-a"
        assert manifest.repositories[0].clone_url == "https://github.com/example/folder-a.git"
        assert manifest.repositories[1].name == "folder-b"
        assert manifest.repositories[1].clone_url == "https://github.com/example/folder-b.git"
