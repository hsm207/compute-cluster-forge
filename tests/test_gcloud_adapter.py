"""Unit tests for gcloud adapter and teardown operations."""

from unittest.mock import patch, MagicMock
from forge.adapters import gcloud
from forge.cli import main


def test_teardown_regional_mig_deletes_mig_and_associated_templates() -> None:
    with (
        patch("subprocess.run") as mock_run,
        patch("forge.adapters.gcloud._execute_gcloud") as mock_exec,
        patch("forge.adapters.gcloud._get_gcloud_binary", return_value="gcloud"),
    ):
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout="projects/test-proj/global/instanceTemplates/dev-spot-template-12345",
        )

        deleted = gcloud.teardown_regional_mig(
            mig_name="dev-box-mig",
            region="us-east5",
            project="test-proj",
            delete_templates=True,
        )

        assert deleted == ["dev-spot-template-12345"]
        assert mock_exec.call_count == 2
        # First call deletes MIG
        assert mock_exec.call_args_list[0][0][0][2:5] == [
            "instance-groups",
            "managed",
            "delete",
        ]
        # Second call deletes instance template
        assert mock_exec.call_args_list[1][0][0][2:5] == [
            "instance-templates",
            "delete",
            "dev-spot-template-12345",
        ]


def test_list_dev_migs_parses_csv_output() -> None:
    with (
        patch("subprocess.run") as mock_run,
        patch("forge.adapters.gcloud._get_gcloud_binary", return_value="gcloud"),
    ):
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout="dev-box-mig,us-east5,1\ndev-box-mig,us-central1,0\n",
        )

        migs = gcloud.list_dev_migs(project="test-proj")
        assert len(migs) == 2
        assert migs[0] == {"name": "dev-box-mig", "region": "us-east5", "size": "1"}
        assert migs[1] == {"name": "dev-box-mig", "region": "us-central1", "size": "0"}


def test_cli_teardown_invokes_teardown_flow() -> None:
    with (
        patch("forge.cli.list_dev_migs") as mock_list,
        patch("forge.cli.teardown_regional_mig") as mock_teardown,
        patch("forge.cli.delete_all_dev_spot_templates") as mock_purge,
    ):
        mock_list.return_value = [
            {"name": "dev-box-mig", "region": "us-east5", "size": "1"}
        ]
        mock_teardown.return_value = ["dev-spot-template-20260925"]
        mock_purge.return_value = []

        ret = main(["teardown", "--all"])
        assert ret == 0
        mock_list.assert_called_once()
        mock_teardown.assert_called_once_with(
            mig_name="dev-box-mig",
            region="us-east5",
            project="compute-cluster-492317",
            delete_templates=True,
        )
        mock_purge.assert_called_once()
