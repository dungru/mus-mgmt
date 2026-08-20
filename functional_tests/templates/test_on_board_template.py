"""Copy this wrapper beside one standardized DUT-side shell script."""

from pathlib import Path

import allure
import pytest

from functional_tests.on_board_runner import on_board_script_fixture


on_board_script = on_board_script_fixture(
    local_script=Path(__file__).parent / "on_board_scripts" / "test_example.sh",
    remote_script="/tmp/mus-test-example.sh",
    fixture_name="on_board_script",
)

CASES = (
    {
        "id": "example-1",
        "title": "Replace with a readable test title",
        "description": "Describe the DUT action and reason for this test.",
        "expected": "Describe the observable expected result.",
    },
)


@pytest.mark.parametrize(
    "case",
    [
        pytest.param(case, id=case["id"])
        for case in CASES
    ],
)
def test_example(on_board_script, case):
    allure.dynamic.title(case["title"])
    allure.dynamic.description(
        f"**Test purpose:** {case['description']}\n\n"
        f"**Expected result:** {case['expected']}"
    )
    with allure.step(f"Verify: {case['expected']}"):
        on_board_script.run_case(case["id"])
