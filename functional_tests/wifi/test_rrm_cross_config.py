"""Allure-visible RRM neighbor cross-configuration test."""

from pathlib import Path

import allure
import pytest

from functional_tests.on_board_runner import on_board_script_fixture


rrm_cross_config_script = on_board_script_fixture(
    local_script=Path(__file__).parent / "on_board_scripts" / "test_rrm_cross_config.sh",
    remote_script="/tmp/mus-test-rrm-cross-config.sh",
    fixture_name="rrm_cross_config_script",
)


@pytest.mark.rrm
def test_rrm_cross_config(rrm_cross_config_script):
    """Cross-configure empty RRM databases and verify every neighbor."""
    allure.dynamic.title("RRM: cross-configure neighbor databases")
    allure.dynamic.description(
        "Requires at least two RRM-capable interfaces and empty neighbor databases. "
        "The script refuses to overwrite a non-empty database, never clears dmesg, "
        "and clears/verifies only entries that it created."
    )
    with allure.step("Verify every interface contains all other interfaces and not itself"):
        rrm_cross_config_script.run_case("1")
