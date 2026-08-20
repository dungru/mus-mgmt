"""Allure-visible firmware-download interface interruption cases."""

from pathlib import Path

import allure
import pytest

from functional_tests.on_board_runner import on_board_script_fixture


fwdl_script = on_board_script_fixture(
    local_script=Path(__file__).parent / "on_board_scripts" / "test_interface_downup_during_fwdl.sh",
    remote_script="/tmp/mus-test-interface-downup-during-fwdl.sh",
    fixture_name="fwdl_script",
)

CASES = (
    (1, "single-sigint", "Handle one SIGINT during first-BSS firmware download", "Bring-up completes and no driver initialization error is logged."),
    (2, "timing-sweep", "Handle SIGINT across the firmware-download timing window", "Every tested delay completes with the interface UP and no driver failure."),
    (3, "sigint-stress", "Survive repeated SIGINT bring-up cycles", "All configured stress iterations complete with the interface UP."),
    (4, "normal-cycles", "Complete normal interface down/up cycles", "All configured control iterations complete successfully."),
)


@pytest.mark.fwdl
@pytest.mark.parametrize(
    "number,case_id,title,expected",
    [pytest.param(*case, id=f"case-{case[0]}-{case[1]}") for case in CASES],
)
def test_interface_downup_during_fwdl(fwdl_script, number, case_id, title, expected):
    """Run one destructive firmware-download regression scenario."""
    del case_id
    allure.dynamic.title(f"FWDL {number}: {title}")
    allure.dynamic.description(
        f"**Expected result:** {expected}\n\nThis case deletes Wi-Fi netdevs to force first-BSS initialization. "
        "It restores the configured Wi-Fi stack plus the original interface states."
    )
    with allure.step(f"Verify: {expected}"):
        fwdl_script.run_case(str(number))
