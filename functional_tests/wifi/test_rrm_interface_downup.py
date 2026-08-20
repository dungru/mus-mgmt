"""Allure-visible RRM interface down/up test."""

from pathlib import Path

import allure
import pytest

from functional_tests.on_board_runner import on_board_script_fixture


rrm_interface_script = on_board_script_fixture(
    local_script=Path(__file__).parent / "on_board_scripts" / "test_rrm_interface_downup.sh",
    remote_script="/tmp/mus-test-rrm-interface-downup.sh",
    fixture_name="rrm_interface_script",
)


@pytest.mark.rrm
def test_rrm_interface_downup(rrm_interface_script):
    """Cycle every discovered RRM interface and validate its procfs data."""
    allure.dynamic.title("RRM: interface down/up recovery")
    allure.dynamic.description(
        "Each discovered RRM interface must transition down and up and expose a "
        "readable SelfNeighborReportElement. Its original UP/DOWN state is restored and verified."
    )
    with allure.step("Verify interface transitions, RRM procfs data, and restoration"):
        rrm_interface_script.run_case("1")
