"""Unit tests for bootstrap logic."""

from pathlib import Path
from unittest.mock import patch, MagicMock
import forge.cloud.bootstrap as bootstrap


def test_install_antigravity_cli_invokes_installer_and_configures_path(
    tmp_path: Path,
) -> None:
    fake_profile_dir = tmp_path / "profile.d"
    fake_profile_dir.mkdir(parents=True, exist_ok=True)
    fake_profile_file = fake_profile_dir / "antigravity.sh"

    fake_bashrc = tmp_path / "bash.bashrc"
    fake_bashrc.write_text("# existing content\n", encoding="utf-8")

    fake_root_bin = tmp_path / "root" / ".local" / "bin" / "agy"
    fake_root_bin.parent.mkdir(parents=True, exist_ok=True)
    fake_root_bin.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")

    fake_usr_bin = tmp_path / "usr" / "local" / "bin" / "agy"
    fake_usr_bin.parent.mkdir(parents=True, exist_ok=True)

    with (
        patch.object(bootstrap, "_run_shell") as mock_shell,
        patch.object(bootstrap, "_run_cmd") as mock_cmd,
        patch.object(bootstrap, "_log") as mock_log,
        patch("forge.cloud.bootstrap.Path") as mock_path_cls,
    ):
        # Let Path behave normally except for mapped system paths
        def fake_path_side_effect(arg):
            p = Path(arg)
            if arg == "/etc/profile.d/antigravity.sh":
                return fake_profile_file
            if arg == "/etc/bash.bashrc":
                return fake_bashrc
            if arg == "/root/.local/bin/agy":
                return fake_root_bin
            if arg == "/usr/local/bin/agy":
                return fake_usr_bin
            if arg == "/home/mohds/.local/bin/agy":
                return tmp_path / "home" / "mohds" / ".local" / "bin" / "agy"
            return p

        mock_path_cls.side_effect = fake_path_side_effect

        bootstrap._install_antigravity_cli()

        mock_shell.assert_called_once_with(
            "export HOME=/root; curl -fsSL --compressed https://antigravity.google/cli/install.sh | bash"
        )
        assert fake_profile_file.exists()
        assert (
            'export PATH="/usr/local/bin:${HOME}/.local/bin:${PATH}"'
            in fake_profile_file.read_text(encoding="utf-8")
        )
        assert "Antigravity CLI PATH" in fake_bashrc.read_text(encoding="utf-8")
