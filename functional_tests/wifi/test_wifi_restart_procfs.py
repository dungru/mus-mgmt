"""Human-readable Allure cases for the DUT-side Wi-Fi procfs test."""

from pathlib import Path

import allure
import pytest

from functional_tests.on_board_runner import on_board_script_fixture


wifi_procfs_script = on_board_script_fixture(
    local_script=(
        Path(__file__).parent
        / "on_board_scripts"
        / "test_wifi_restart_procfs.sh"
    ),
    remote_script="/tmp/mus-wifi-restart-procfs.sh",
    fixture_name="wifi_procfs_script",
)


CASE_DEFINITIONS = (
    {
        "number": 1,
        "id": "interface-bringup",
        "title": "Create procfs entries after interface bring-up",
        "description": (
            "Bring up the first Wi-Fi interface and inspect its procfs "
            "directory, RRM file, and channels.json."
        ),
        "expected": "The interface procfs directory and required files exist and are readable.",
    },
    {
        "number": 2,
        "id": "interface-restart",
        "title": "Restart one interface without affecting others",
        "description": (
            "Bring the first Wi-Fi interface down and up while checking that "
            "the second interface RRM file remains available."
        ),
        "expected": (
            "The restarted interface procfs entries are removed and recreated "
            "while other interfaces remain operational."
        ),
    },
    {
        "number": 3,
        "id": "multi-interface-stability",
        "title": "Maintain stability across multiple interfaces",
        "description": (
            "Bring up all ra* interfaces, restart one interface, and verify "
            "that another interface remains unaffected."
        ),
        "expected": (
            "The procfs entry count matches the interface count and restarting "
            "one interface does not affect the others."
        ),
    },
    {
        "number": 4,
        "id": "rapid-restart-stress",
        "title": "Complete five rapid restart cycles",
        "description": "Perform five consecutive down/up cycles on the first Wi-Fi interface.",
        "expected": "RRM SelfNeighborReportElement remains available after every cycle.",
    },
    {
        "number": 5,
        "id": "all-interface-restart",
        "title": "Restart all Wi-Fi interfaces",
        "description": (
            "Bring down all Wi-Fi interfaces, start the main interfaces, wait "
            "for firmware initialization, and restore virtual interfaces."
        ),
        "expected": "All procfs interface entries are removed and then fully restored.",
    },
    {
        "number": 6,
        "id": "wifi-reload",
        "title": "Restore procfs after wifi reload",
        "description": (
            "Run wifi reload, wait for Wi-Fi initialization, and check "
            "interfaces, channels.json, and RRM."
        ),
        "expected": (
            "The interface count does not decrease and all required procfs "
            "files exist after reload."
        ),
    },
    {
        "number": 7,
        "id": "wifi-restart",
        "title": "Restore procfs after wifi restart",
        "description": (
            "Run wifi restart and verify interface recovery, channels.json, "
            "and repeated read stability."
        ),
        "expected": "Interfaces and required procfs files are fully restored and remain readable.",
    },
)
CASE_BY_NUMBER = {case["number"]: case for case in CASE_DEFINITIONS}


def select_cases(value):
    """Resolve ``all``, one case number, or a comma-separated case list."""
    normalized = value.strip().lower()
    if normalized == "all":
        return list(CASE_DEFINITIONS)

    tokens = [token.strip() for token in normalized.split(",")]
    if not tokens or any(not token.isdigit() for token in tokens):
        raise ValueError("--wifi-case must be all, 1-7, or a list such as 1,3,7")

    selected = []
    for token in tokens:
        number = int(token)
        if number not in CASE_BY_NUMBER:
            raise ValueError("--wifi-case must be all, 1-7, or a list such as 1,3,7")
        if CASE_BY_NUMBER[number] not in selected:
            selected.append(CASE_BY_NUMBER[number])
    return selected


def pytest_generate_tests(metafunc):
    """Expose every selected shell case as a separately reported pytest case."""
    if "wifi_case" not in metafunc.fixturenames:
        return
    try:
        cases = select_cases(metafunc.config.getoption("--wifi-case"))
    except ValueError as error:
        raise pytest.UsageError(str(error)) from error
    parameters = [
        pytest.param(item, id=f"case-{item['number']}-{item['id']}")
        for item in cases
    ]
    metafunc.parametrize("wifi_case", parameters)


@pytest.mark.wifi_restart
def test_wifi_restart_procfs(wifi_procfs_script, wifi_case):
    """Run one named DUT Wi-Fi case and preserve its evidence in Allure."""
    number = wifi_case["number"]
    allure.dynamic.title(f"Wi-Fi procfs {number}: {wifi_case['title']}")
    allure.dynamic.description(
        f"**Test purpose:** {wifi_case['description']}\n\n"
        f"**Expected result:** {wifi_case['expected']}\n\n"
        "The shared script follows MUS_RESULT_V1 and is deployed during "
        "framework setup. Allure contains its SSH command, parsed result, "
        "restore status, and complete DUT log."
    )
    with allure.step(f"Verify: {wifi_case['expected']}"):
        wifi_procfs_script.run_case(str(number))
