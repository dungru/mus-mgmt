"""Shared controller-side bootstrap for functional DUT tests."""

from __future__ import annotations

import json
import traceback
from pathlib import Path

import allure
import pytest
from ansible import context
from ansible.module_utils.common.collections import ImmutableDict
from ansible.utils import display

from apis.ansible import AdHoc
from apis.dut import create_dut
from apis.utils import AttrDict
from functional_tests.on_board_runner import (
    OnBoardFrameworkError,
    RESTORE_MODES,
)


ENVIRONMENTS_DIR = Path(__file__).parent / "environments"


class FrameworkSetupError(RuntimeError):
    """A controller or DUT preparation failure that prevents case execution."""


def pytest_addoption(parser):
    """Register functional-suite controls before pytest parses test paths."""
    group = parser.getgroup("functional test controls")
    group.addoption("--environment", action="store", default="dut115")
    group.addoption("--apply-dut-config", action="store_true")
    group.addoption(
        "--reboot-after-config",
        action="store_true",
        help="Reboot and wait for SSH after applying the declared DUT bundle",
    )
    group.addoption("--ssh-health-timeout", type=int, default=120)
    group.addoption(
        "--wifi-case",
        action="store",
        default="all",
        help="Wi-Fi procfs case: all, one number, or a comma-separated list",
    )
    group.addoption(
        "--handler-chain",
        "--handler_chain",
        dest="handler_chain",
        action="store",
        default="cli,vtysh,json",
    )
    group.addoption(
        "--continue-on-failure",
        action="store_true",
        help=(
            "Run every selected functional case after failures and remove "
            "temporary DUT scripts at the end (for CI/CD)."
        ),
    )
    group.addoption(
        "--restore-mode",
        choices=RESTORE_MODES,
        default=None,
        help=(
            "DUT restore policy for on-board scripts. Defaults to on-success "
            "for RD runs and always for --continue-on-failure."
        ),
    )


def _maxfail_was_supplied(config):
    """Return whether the caller explicitly chose pytest's failure limit."""
    args = config.invocation_params.args
    return any(
        argument == "-x"
        or argument == "--maxfail"
        or argument.startswith("--maxfail=")
        for argument in args
    )


def pytest_configure(config):
    config.addinivalue_line("markers", "wifi_restart: Wi-Fi restart/procfs test")
    config.addinivalue_line("markers", "channels_json: Wi-Fi channels.json test")
    config.addinivalue_line("markers", "rrm: radio resource management test")
    config.addinivalue_line("markers", "fwdl: firmware-download regression test")

    if config.getoption("--continue-on-failure"):
        restore_mode = config.getoption("--restore-mode")
        if restore_mode not in (None, "always"):
            raise pytest.UsageError(
                "--continue-on-failure requires --restore-mode=always"
            )
        config.option.maxfail = 0
    elif not _maxfail_was_supplied(config):
        # Interactive runs stop on the first failure so the DUT is left in the
        # exact state that caused it.
        config.option.maxfail = 1


@pytest.hookimpl(hookwrapper=True, tryfirst=True)
def pytest_runtest_makereport(item, call):
    """Track on-board failures and stop when framework state is untrustworthy."""
    outcome = yield
    report = outcome.get_result()
    state = getattr(item.module, "_mus_on_board_run_state", None)
    if state is None or not report.failed:
        return

    state.failed = True
    state.failures.append(f"{item.nodeid} [{report.when}]")
    if call.excinfo is not None and isinstance(
        call.excinfo.value, OnBoardFrameworkError
    ):
        state.framework_failed = True
        item.session.shouldstop = (
            "On-board framework/restore failure: DUT baseline is not trustworthy"
        )


def _environment_file(request):
    environment_name = request.config.getoption("--environment")
    inventory_file = ENVIRONMENTS_DIR / f"{environment_name}.yml"
    if not inventory_file.is_file():
        raise pytest.UsageError(
            f"Functional environment file not found: {inventory_file}"
        )
    return inventory_file


def _attach_framework_error(error):
    allure.attach(
        traceback.format_exc(),
        "framework setup traceback",
        allure.attachment_type.TEXT,
    )
    allure.attach(
        f"{type(error).__name__}: {error}",
        "framework setup error",
        allure.attachment_type.TEXT,
    )


@pytest.fixture(scope="session")
def adhoc(request):
    """Create the minimal Ansible controller used by functional suites.

    This intentionally replaces ``apis.fixtures`` for functional tests so its
    traffic-generator and monkeypatch autouse fixtures do not obscure Allure.
    """
    context.CLIARGS = ImmutableDict(
        connection="smart",
        verbosity=request.config.getoption("--verbosity"),
        become_user="root",
        become_method="sudo",
    )
    ansible_display = display.Display()
    ansible_display.verbosity = request.config.getoption("--verbosity")
    return AdHoc(str(_environment_file(request)))


@pytest.fixture(scope="session")
def topo(request, adhoc):
    """Build platform-specific DUT objects without a teardown callback."""
    try:
        handler_chain = [
            name.strip().upper()
            for name in request.config.getoption("--handler-chain").split(",")
            if name.strip()
        ]
        if not handler_chain:
            raise pytest.UsageError("--handler-chain must contain a handler")

        result = AttrDict()
        with allure.step("Framework setup: build DUT connections"):
            for host in adhoc.hosts:
                system = host.vars.get("vars", {}).get("dut_system")
                if system is None:
                    raise pytest.UsageError(
                        f"{host.name} must declare vars.dut_system"
                    )
                result[host.name] = create_dut(adhoc, host, system, handler_chain)
        return result
    except pytest.UsageError:
        raise
    except Exception as error:
        _attach_framework_error(error)
        raise FrameworkSetupError("Could not create DUT connections") from error


def _apply_config_bundle(dut, config):
    bundle_root = (ENVIRONMENTS_DIR / config["folder"]).resolve()
    if not bundle_root.is_dir():
        raise FileNotFoundError(f"DUT config bundle not found: {bundle_root}")

    allure.attach(
        json.dumps(
            {
                "dut": dut.name,
                "address": dut.ipaddr,
                "bundle": str(bundle_root),
                "mappings": config["mappings"],
            },
            indent=2,
        ),
        "DUT config bundle",
        allure.attachment_type.JSON,
    )
    backup_root = dut.apply_config_bundle(bundle_root, config["mappings"])
    allure.attach(
        f"DUT backup retained at: {backup_root}",
        "DUT config backup",
        allure.attachment_type.TEXT,
    )


@pytest.fixture(scope="session", autouse=True)
def dut_ready(request, topo):
    """Optionally configure the DUT, then verify SSH before any test body."""
    try:
        if request.config.getoption("--apply-dut-config"):
            with allure.step("Framework setup: apply declared DUT config bundle"):
                for dut in topo.values():
                    config = dut.vars.get("dut_config")
                    if config is not None:
                        _apply_config_bundle(dut, config)

            if request.config.getoption("--reboot-after-config"):
                with allure.step("Framework setup: reboot DUT after config"):
                    for dut in topo.values():
                        dut.reboot()

        timeout = request.config.getoption("--ssh-health-timeout")
        with allure.step("Framework setup: verify DUT SSH and shell"):
            for dut in topo.values():
                dut.wait_for_ssh(timeout)
                response = dut.shell("echo mus-mgmt-functional-ready")
                if response.strip() != "mus-mgmt-functional-ready":
                    raise RuntimeError(
                        f"Unexpected health-check response from {dut.name}: {response!r}"
                    )
        return topo
    except Exception as error:
        _attach_framework_error(error)
        raise FrameworkSetupError("DUT framework setup failed") from error
