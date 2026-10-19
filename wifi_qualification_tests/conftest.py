"""Controller-side bootstrap for the SpaceX/Candela Wi-Fi qualification suite."""

from __future__ import annotations

import json
import shlex
import subprocess
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
CANDELA_DIR = Path(__file__).parent / "candela"


class FrameworkSetupError(RuntimeError):
    """A controller or DUT preparation failure that prevents case execution."""


class LANforgeRunError(RuntimeError):
    """A LANforge py-script returned a non-zero exit code."""


class LANforgeRunner:
    """Run a LANforge py-script on the LANforge server via SSH (BatchMode=yes)."""

    def __init__(self, lf_config: dict):
        self.host = lf_config["host"]
        self.user = lf_config["user"]
        self.scripts_path = lf_config["scripts_path"]
        self._subs = {
            "LF_MGR_IP": lf_config["host"],
            "UPSTREAM_PORT": lf_config["upstream_port"],
            "REPORT_PATH": lf_config.get("report_path", "/home/lanforge/lf_reports"),
            "TEST_RIG": lf_config.get("test_rig", "LANforge"),
        }

    @property
    def target(self):
        return f"{self.user}@{self.host}"

    def _run(self, command, attachment_name):
        result = subprocess.run(command, capture_output=True, text=True, timeout=720)
        record = "$ " + shlex.join(command) + "\n"
        record += f"exit_code={result.returncode}\n"
        record += "--- stdout ---\n" + result.stdout
        record += "\n--- stderr ---\n" + result.stderr
        allure.attach(record, attachment_name, allure.attachment_type.TEXT)
        return result

    def run_suite_entry(self, entry: dict) -> None:
        """Execute one test_suites entry; raise LANforgeRunError on non-zero exit."""
        if entry.get("enabled", "TRUE") == "FALSE":
            pytest.skip(f"Suite entry disabled (enabled=FALSE): {entry.get('command', '?')}")

        script = entry["command"]
        args_str = " ".join(entry.get("args_list", []))
        for placeholder, value in self._subs.items():
            args_str = args_str.replace(placeholder, value)

        remote_cmd = f"cd {self.scripts_path} && python3 {script} {args_str}"
        result = self._run(
            [
                "ssh",
                "-o", "BatchMode=yes",
                "-o", "StrictHostKeyChecking=accept-new",
                self.target,
                remote_cmd,
            ],
            "LANforge test command",
        )
        if result.returncode != 0:
            raise LANforgeRunError(
                f"{script} failed (rc={result.returncode})"
            )


def pytest_addoption(parser):
    group = parser.getgroup("wifi qualification test controls")
    group.addoption("--environment", action="store", default="dut106")
    group.addoption("--ssh-health-timeout", type=int, default=120)
    group.addoption(
        "--continue-on-failure",
        action="store_true",
        help="Run every case after failures and remove DUT scripts at the end (CI/CD).",
    )
    group.addoption(
        "--restore-mode",
        choices=RESTORE_MODES,
        default=None,
        help="DUT restore policy. Defaults to on-success; always when --continue-on-failure.",
    )
    group.addoption(
        "--skip-lanforge",
        action="store_true",
        help="Skip Step 2 (LANforge client association); run DUT-only verification.",
    )


def _maxfail_was_supplied(config):
    args = config.invocation_params.args
    return any(
        a == "-x" or a == "--maxfail" or a.startswith("--maxfail=")
        for a in args
    )


def pytest_configure(config):
    config.addinivalue_line("markers", "wifi_qualification: SpaceX/Candela qualification suite")

    if config.getoption("--continue-on-failure"):
        restore_mode = config.getoption("--restore-mode")
        if restore_mode not in (None, "always"):
            raise pytest.UsageError("--continue-on-failure requires --restore-mode=always")
        config.option.maxfail = 0
    elif not _maxfail_was_supplied(config):
        config.option.maxfail = 1


@pytest.hookimpl(hookwrapper=True, tryfirst=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    report = outcome.get_result()
    state = getattr(item.module, "_mus_on_board_run_state", None)
    if state is None or not report.failed:
        return
    state.failed = True
    state.failures.append(f"{item.nodeid} [{report.when}]")
    if call.excinfo is not None and isinstance(call.excinfo.value, OnBoardFrameworkError):
        state.framework_failed = True
        item.session.shouldstop = (
            "On-board framework/restore failure: DUT baseline is not trustworthy"
        )


@pytest.fixture(scope="session")
def adhoc(request):
    env_name = request.config.getoption("--environment")
    inv = ENVIRONMENTS_DIR / f"{env_name}.yml"
    if not inv.is_file():
        raise pytest.UsageError(f"Environment file not found: {inv}")
    context.CLIARGS = ImmutableDict(
        connection="smart",
        verbosity=request.config.getoption("--verbosity"),
        become_user="root",
        become_method="sudo",
    )
    display.Display().verbosity = request.config.getoption("--verbosity")
    return AdHoc(str(inv))


@pytest.fixture(scope="session")
def topo(adhoc):
    result = AttrDict()
    with allure.step("Framework setup: build DUT connections"):
        for host in adhoc.hosts:
            system = host.vars.get("vars", {}).get("dut_system")
            if system is None:
                raise pytest.UsageError(f"{host.name} must declare vars.dut_system")
            result[host.name] = create_dut(adhoc, host, system, ["CLI"])
    return result


@pytest.fixture(scope="session", autouse=True)
def dut_ready(request, topo):
    """Verify SSH health before any test body runs."""
    try:
        timeout = request.config.getoption("--ssh-health-timeout")
        with allure.step("Framework setup: verify DUT SSH and shell"):
            for dut in topo.values():
                dut.wait_for_ssh(timeout)
                resp = dut.shell("echo mus-mgmt-qualification-ready")
                if resp.strip() != "mus-mgmt-qualification-ready":
                    raise RuntimeError(f"Unexpected health-check from {dut.name}: {resp!r}")
        return topo
    except Exception as error:
        allure.attach(traceback.format_exc(), "framework setup traceback", allure.attachment_type.TEXT)
        allure.attach(f"{type(error).__name__}: {error}", "framework setup error", allure.attachment_type.TEXT)
        raise FrameworkSetupError("DUT framework setup failed") from error


@pytest.fixture(scope="session")
def lanforge(request, adhoc):
    """Connect to the LANforge server configured in the environment YAML.

    Returns None when --skip-lanforge is set so tests can skip Step 2 cheaply.
    """
    if request.config.getoption("--skip-lanforge"):
        return None
    lf_config = adhoc.group_vars.get("lanforge")
    if lf_config is None:
        raise pytest.UsageError(
            "Environment YAML must declare vars.lanforge "
            "(host, user, scripts_path, upstream_port)"
        )
    with allure.step("Framework setup: verify LANforge SSH"):
        scripts_path = lf_config["scripts_path"]
        user = lf_config["user"]
        host = lf_config["host"]
        check = subprocess.run(
            [
                "ssh", "-o", "BatchMode=yes",
                "-o", "StrictHostKeyChecking=accept-new",
                f"{user}@{host}",
                f"test -f {scripts_path}/sta_connect2.py && echo ok",
            ],
            capture_output=True, text=True, timeout=30,
        )
        if check.returncode != 0 or "ok" not in check.stdout:
            raise FrameworkSetupError(
                f"LANforge SSH health check failed (rc={check.returncode}): {check.stderr}"
            )
    return LANforgeRunner(lf_config)


@pytest.fixture(scope="session")
def tests_json():
    """Load the Candela test-suite JSON for test 1.3 and return the test_suites dict."""
    json_path = CANDELA_DIR / "ct_1_3_security_modes_tests.json"
    if not json_path.is_file():
        raise pytest.UsageError(f"Candela test JSON not found: {json_path}")
    data = json.loads(json_path.read_text())
    return data["test_suites"]
