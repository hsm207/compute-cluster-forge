"""Unit tests for Git adapter with Humble Object isolation."""

from pathlib import Path
import tempfile
import pytest

from forge.adapters.git import get_origin_url, GitAdapterError


def test_get_origin_url_nonexistent_directory() -> None:
    with pytest.raises(GitAdapterError, match="Directory does not exist"):
        get_origin_url(Path("C:/nonexistent/path/that/does/not/exist"))


def test_get_origin_url_non_git_directory() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        with pytest.raises(GitAdapterError, match="Directory is not a git repository"):
            get_origin_url(Path(tmp_dir))
