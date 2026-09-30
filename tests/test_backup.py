"""Unit tests for preemption backup logic (MECE 3-way branching)."""

from pathlib import Path
from unittest.mock import patch, MagicMock
import forge.cloud.backup as backup


def test_main_case_1_uncommitted_changes(tmp_path: Path) -> None:
    """Case 1: When repo is dirty, it must create and push a spot-backup branch."""
    repo = tmp_path / "repo1"
    repo.mkdir()
    (repo / ".git").mkdir()

    with (
        patch("forge.cloud.backup._setup_logging"),
        patch("forge.cloud.backup._fetch_github_token", return_value="fake-token"),
        patch("forge.cloud.backup._find_git_repositories", return_value=[repo]),
        patch("forge.cloud.backup._is_dirty", return_value=True),
        patch("forge.cloud.backup._has_unpushed_commits") as mock_unpushed,
        patch("forge.cloud.backup._backup_dirty_repo") as mock_backup_dirty,
        patch("forge.cloud.backup._push_current_branch") as mock_push_current,
    ):
        backup.main()

        mock_backup_dirty.assert_called_once()
        args = mock_backup_dirty.call_args[0]
        assert args[0] == repo
        assert args[1].startswith("spot-backup-")
        assert args[2] == "fake-token"

        mock_unpushed.assert_not_called()
        mock_push_current.assert_not_called()


def test_main_case_2_clean_tree_with_unpushed_commits(tmp_path: Path) -> None:
    """Case 2: When repo is clean but has unpushed commits, it must push current branch."""
    repo = tmp_path / "repo2"
    repo.mkdir()
    (repo / ".git").mkdir()

    with (
        patch("forge.cloud.backup._setup_logging"),
        patch("forge.cloud.backup._fetch_github_token", return_value="fake-token"),
        patch("forge.cloud.backup._find_git_repositories", return_value=[repo]),
        patch("forge.cloud.backup._is_dirty", return_value=False),
        patch("forge.cloud.backup._has_unpushed_commits", return_value=True),
        patch("forge.cloud.backup._backup_dirty_repo") as mock_backup_dirty,
        patch("forge.cloud.backup._push_current_branch") as mock_push_current,
    ):
        backup.main()

        mock_push_current.assert_called_once_with(repo, "fake-token")
        mock_backup_dirty.assert_not_called()


def test_main_case_3_clean_and_fully_pushed(tmp_path: Path) -> None:
    """Case 3: When repo is clean and has no unpushed commits, do nothing."""
    repo = tmp_path / "repo3"
    repo.mkdir()
    (repo / ".git").mkdir()

    with (
        patch("forge.cloud.backup._setup_logging"),
        patch("forge.cloud.backup._fetch_github_token", return_value="fake-token"),
        patch("forge.cloud.backup._find_git_repositories", return_value=[repo]),
        patch("forge.cloud.backup._is_dirty", return_value=False),
        patch("forge.cloud.backup._has_unpushed_commits", return_value=False),
        patch("forge.cloud.backup._backup_dirty_repo") as mock_backup_dirty,
        patch("forge.cloud.backup._push_current_branch") as mock_push_current,
    ):
        backup.main()

        mock_backup_dirty.assert_not_called()
        mock_push_current.assert_not_called()


def test_has_unpushed_commits_detects_ahead_commits() -> None:
    """Test _has_unpushed_commits when git rev-list returns count > 0."""
    with patch("subprocess.run") as mock_run:
        # Mock rev-list @{u}..HEAD
        mock_run.return_value = MagicMock(returncode=0, stdout="3\n")
        assert backup._has_unpushed_commits(Path("/fake/repo")) is True

        # Mock rev-list count 0
        mock_run.return_value = MagicMock(returncode=0, stdout="0\n")
        assert backup._has_unpushed_commits(Path("/fake/repo")) is False


def test_push_current_branch_invokes_git_push() -> None:
    """Test _push_current_branch executes git push with authenticated url."""
    with (
        patch("forge.cloud.backup._get_current_branch", return_value="feat-quiz"),
        patch("forge.cloud.backup._get_remote_url", return_value="https://github.com/hsm207/parro-3"),
        patch("subprocess.run") as mock_run,
    ):
        mock_run.return_value = MagicMock(returncode=0, stderr="")
        fake_path = Path("/fake/repo")
        backup._push_current_branch(fake_path, "token123")

        mock_run.assert_called_once()
        cmd = mock_run.call_args[0][0]
        assert cmd[:4] == ["git", "-C", str(fake_path), "push"]
        assert cmd[4:6] == ["-u", "https://oauth2:token123@github.com/hsm207/parro-3"]
        assert cmd[6] == "feat-quiz"
