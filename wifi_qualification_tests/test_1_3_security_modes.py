"""Allure-visible cases for 1.3 Client Connectivity - Security Modes.

SpaceX/Candela Wi-Fi Chipset Qualification Test Scenarios, test 1.3.
DUT: MT7999 tri-band AP (ra0=2.4G, rai0=5G, rax0=6G) at 192.168.5.106.

Each case reconfigures all three bands to a single security mode, verifies
the AP advertises the correct AKM/cipher suite via iwpriv (Step 1), then
drives 64 LANforge virtual clients per band to associate and measures
DHCP time, 4-way/SAE time, and total connect time (Step 2).
"""

from pathlib import Path

import allure
import pytest

from functional_tests.on_board_runner import on_board_script_fixture


security_modes_script = on_board_script_fixture(
    local_script=(
        Path(__file__).parent
        / "on_board_scripts"
        / "test_1_3_security_modes.sh"
    ),
    remote_script="/tmp/mus-test-security-modes.sh",
    fixture_name="security_modes_script",
)

CASES = (
    (
        1,
        "open",
        "Open (no authentication)",
        "AP beacons with an open BSS on all bands; no RSN IE present.",
    ),
    (
        2,
        "wpa2-psk",
        "WPA2-PSK (PMF optional)",
        "AP advertises RSN with CCMP cipher and PSK AKM; PMF optional.",
    ),
    (
        3,
        "wpa3-sae-h2e",
        "WPA3-SAE H2E (PMF required)",
        "AP advertises SAE AKM with H2E-only flag; PMF required.",
    ),
    (
        4,
        "wpa2-wpa3-transition",
        "WPA2/WPA3 Transition (PMF optional)",
        "AP advertises both PSK and SAE AKMs simultaneously; PMF optional.",
    ),
    (
        5,
        "wpa3-enterprise",
        "WPA3-Enterprise 802.1X/RADIUS (PMF required)",
        "AP configured with EAP/RADIUS AKM; case skipped if no RADIUS available.",
    ),
    (
        6,
        "owe",
        "OWE - Opportunistic Wireless Encryption (PMF required)",
        "AP advertises OWE AKM; PMF required; open association with encrypted link.",
    ),
)


@pytest.mark.wifi_qualification
@pytest.mark.parametrize(
    "number,case_id,title,expected",
    [pytest.param(*case, id=f"case-{case[0]}-{case[1]}") for case in CASES],
)
def test_1_3_security_modes(
    security_modes_script,
    lanforge,
    tests_json,
    request,
    number,
    case_id,
    title,
    expected,
):
    """Configure one security mode on all bands, verify DUT advertisement, then run LANforge clients."""
    allure.dynamic.title(f"1.3 Security Modes {number}: {title}")
    allure.dynamic.description(
        f"**Test purpose:** Configure the DUT to use {title} on all three bands "
        f"(ra0 2.4G / rai0 5G / rax0 6G) and verify the AP correctly advertises "
        f"the AKM and cipher suite.\n\n"
        f"**Expected result:** {expected}\n\n"
        "Step 1: The DUT script follows MUS_RESULT_V1, restores the original UCI "
        "encryption settings after each case, and waits for Wi-Fi to reinitialise.\n\n"
        "Step 2: 64 LANforge virtual clients per band attempt association and DHCP; "
        "KPIs: 100% association success, total connect time < 2 s per client."
    )

    with allure.step(f"Step 1 – DUT: verify {title} advertisement"):
        security_modes_script.run_case(str(number))

    if not request.config.getoption("--skip-lanforge"):
        for band in ("2g", "5g", "6g"):
            suite_key = f"1_3_{case_id}_{band}"
            band_entries = tests_json.get(suite_key)
            if band_entries is None:
                pytest.skip(f"No suite entry found for key {suite_key!r}")
            entry = next(iter(band_entries.values()))
            with allure.step(
                f"Step 2 – LANforge {band.upper()}: 64 stations, {title}"
            ):
                lanforge.run_suite_entry(entry)
