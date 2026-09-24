"""Humble object adapter for local Git operations."""

from __future__ import annotations

from pathlib import Path
import subprocess


class GitAdapterError(Exception):
    """Raised when a Git command fails."""


def get_origin_url(repo_dir: Path) -> str:
    """Retrieve the 'origin' remote URL for a local git repository.

    Args:
        repo_dir: Absolute path to the git repository folder.

    Returns:
        The origin remote URL string.

    Raises:
        GitAdapterError: If the directory is not a git repo or remote is missing.
    """
    if not repo_dir.exists():
        raise GitAdapterError(f"Directory does not exist: {repo_dir}")

    git_dir = repo_dir / ".git"
    if not git_dir.exists():
        raise GitAdapterError(f"Directory is not a git repository: {repo_dir}")

    try:
        result = subprocess.run(
            ["git", "-C", str(repo_dir), "remote", "get-url", "origin"],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as exc:
        stderr_msg = exc.stderr.strip() if exc.stderr else "Unknown error"
        raise GitAdapterError(
            f"Failed to get origin URL for {repo_dir.name}: {stderr_msg}"
        ) from exc


def get_git_author_identity() -> tuple[str, str]:
    """Retrieve global Git user.name and user.email from local environment.

    Returns:
        A tuple of (user_name, user_email). Falls back to empty strings if unset.
    """
    def _read_config(key: str) -> str:
        try:
            result = subprocess.run(
                ["git", "config", "--get", key],
                capture_output=True,
                text=True,
                check=True,
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError:
            return ""

    user_name = _read_config("user.name")
    user_email = _read_config("user.email")
    return user_name, user_email

