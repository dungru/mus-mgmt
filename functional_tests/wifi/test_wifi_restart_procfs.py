"""Human-readable Allure cases for the DUT-side Wi-Fi procfs test."""

import allure
import pytest

from wifi.case_catalog import select_cases
from wifi.wifi_runner import WifiScriptRunner


def pytest_generate_tests(metafunc):
    """Expose every selected shell case as a separately reported pytest case."""
    if "wifi_case" not in metafunc.fixturenames:
        return
    try:
        cases = select_cases(metafunc.config.getoption("--wifi-case"))
    except ValueError as error:
        raise pytest.UsageError(str(error)) from error
    metafunc.parametrize(
        "wifi_case",
        cases,
        ids=[f"case-{item['number']}-{item['id']}" for item in cases],
    )


@pytest.mark.wifi_restart
def test_wifi_restart_procfs(topo, wifi_case):
    """Run one named DUT Wi-Fi case and preserve its evidence in Allure."""
    number = wifi_case["number"]
    allure.dynamic.title(f"Wi-Fi procfs {number}: {wifi_case['title']}")
    allure.dynamic.description(
        f"**Test purpose:** {wifi_case['description']}\n\n"
        f"**Expected result:** {wifi_case['expected']}\n\n"
        "This case runs on the DUT. Allure attachments contain the SCP and "
        "SSH commands and the complete DUT log."
    )
    with allure.step(f"Verify: {wifi_case['expected']}"):
        WifiScriptRunner(topo.dut1).run_procfs_case(str(number))
