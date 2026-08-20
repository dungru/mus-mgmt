"""Allure-visible cases for channels.json behavior."""

from pathlib import Path

import allure
import pytest

from functional_tests.on_board_runner import on_board_script_fixture


channels_json_script = on_board_script_fixture(
    local_script=Path(__file__).parent / "on_board_scripts" / "test_channels_json.sh",
    remote_script="/tmp/mus-test-channels-json.sh",
    fixture_name="channels_json_script",
)

CASES = (
    (1, "presence", "Expose channels.json only on main interfaces", "Main interfaces expose channels.json and virtual interfaces do not."),
    (2, "structure", "Validate channels.json structure", "Every readable file contains the required JSON fields and valid JSON when jq is available."),
    (3, "repeated-read", "Read channels.json repeatedly", "Ten consecutive reads succeed without malformed or missing band data."),
    (4, "band", "Read band information", "Every main interface reports non-empty band information."),
    (5, "interface-restart", "Recreate channels.json after interface restart", "The file disappears while down and returns with consistent band data after up."),
    (6, "wifi-reload-restart", "Preserve channels.json across Wi-Fi reload and restart", "All main interfaces recover their channels.json files and repeated reads succeed."),
    (7, "legacy-band-directories", "Reject legacy band directories", "/proc/mt_wifi/band0 and band1 are absent."),
)


@pytest.mark.channels_json
@pytest.mark.parametrize(
    "number,case_id,title,expected",
    [pytest.param(*case, id=f"case-{case[0]}-{case[1]}") for case in CASES],
)
def test_channels_json(channels_json_script, number, case_id, title, expected):
    """Run one independently reported DUT-side channels.json case."""
    del case_id
    allure.dynamic.title(f"channels.json {number}: {title}")
    allure.dynamic.description(f"**Expected result:** {expected}\n\nThe DUT script restores and verifies its pre-test interface state according to the selected restore mode.")
    with allure.step(f"Verify: {expected}"):
        channels_json_script.run_case(str(number))
