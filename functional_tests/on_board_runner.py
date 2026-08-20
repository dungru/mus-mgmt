"""Standard transport, result parsing, and lifecycle for DUT-side shell tests."""

from __future__ import annotations

import json
import shlex
import subprocess
from dataclasses import asdict, dataclass, field
from pathlib import Path

import allure
import pytest


RESULT_PREFIX = "MUS_RESULT_V1|"
RESTORE_MODES = ("always", "on-success", "never")


class OnBoardFrameworkError(RuntimeError):
    """The controller or shell contract failed outside a test assertion."""


class OnBoardProtocolError(OnBoardFrameworkError):
    """The shell script did not emit a valid MUS_RESULT_V1 record."""


class OnBoardRestoreError(OnBoardFrameworkError):
    """The DUT could not be proven to match its pre-test state."""


@dataclass(frozen=True)
class OnBoardResult:
    case: str
    test: str
    restore: str
    passed: int
    failed: int
    skipped: int


@dataclass
class OnBoardRunState:
    failed: bool = False
    framework_failed: bool = False
    failures: list[str] = field(default_factory=list)


def resolve_restore_mode(config):
    """Choose the safe policy for interactive or CI execution."""
    requested = config.getoption("--restore-mode")
    if requested is not None:
        return requested
    if config.getoption("--continue-on-failure"):
        return "always"
    return "on-success"


def parse_result(stdout, expected_case):
    """Parse and validate the one machine-readable result emitted by a script."""
    records = [
        line.strip()
        for line in stdout.splitlines()
        if line.strip().startswith(RESULT_PREFIX)
    ]
    if len(records) != 1:
        raise OnBoardProtocolError(
            "Expected exactly one MUS_RESULT_V1 record, "
            f"received {len(records)}"
        )

    values = {}
    for field_value in records[0][len(RESULT_PREFIX) :].split("|"):
        name, separator, value = field_value.partition("=")
        if not separator or not name or name in values:
            raise OnBoardProtocolError(
                f"Malformed MUS_RESULT_V1 field: {field_value!r}"
            )
        values[name] = value

    required = {"case", "test", "restore", "passed", "failed", "skipped"}
    missing = required.difference(values)
    if missing:
        raise OnBoardProtocolError(
            f"MUS_RESULT_V1 is missing fields: {', '.join(sorted(missing))}"
        )
    if values["case"] != str(expected_case):
        raise OnBoardProtocolError(
            f"Requested case {expected_case!r}, received {values['case']!r}"
        )
    if values["test"] not in {"PASS", "FAIL", "SKIP", "ERROR"}:
        raise OnBoardProtocolError(f"Invalid test status: {values['test']!r}")
    if values["restore"] not in {
        "PASS",
        "FAIL",
        "PRESERVED",
        "NOT_REQUIRED",
    }:
        raise OnBoardProtocolError(
            f"Invalid restore status: {values['restore']!r}"
        )

    try:
        counters = {
            name: int(values[name]) for name in ("passed", "failed", "skipped")
        }
    except ValueError as error:
        raise OnBoardProtocolError("Result counters must be integers") from error
    if any(value < 0 for value in counters.values()):
        raise OnBoardProtocolError("Result counters cannot be negative")
    if values["test"] == "PASS" and counters["failed"] != 0:
        raise OnBoardProtocolError("PASS result contains failed assertions")
    if values["test"] == "FAIL" and counters["failed"] == 0:
        raise OnBoardProtocolError("FAIL result contains no failed assertions")

    return OnBoardResult(
        case=values["case"],
        test=values["test"],
        restore=values["restore"],
        **counters,
    )


class OnBoardScriptRunner:
    """Deploy and execute one self-contained MUS contract shell script."""

    def __init__(
        self,
        dut,
        local_script,
        remote_script,
        restore_mode="on-success",
    ):
        if restore_mode not in RESTORE_MODES:
            raise ValueError(f"Unsupported restore mode: {restore_mode}")
        self.dut = dut
        self.local_script = Path(local_script)
        self.remote_script = remote_script
        self.restore_mode = restore_mode
        self.user = dut._adhoc.group_vars.get("ansible_ssh_user", "root")

    @property
    def target(self):
        return f"{self.user}@{self.dut.ipaddr}"

    def _run(self, command, attachment_name):
        result = subprocess.run(command, capture_output=True, text=True)
        record = "$ " + shlex.join(command) + "\n"
        record += f"exit_code={result.returncode}\n"
        record += "--- stdout ---\n" + result.stdout
        record += "\n--- stderr ---\n" + result.stderr
        allure.attach(record, attachment_name, allure.attachment_type.TEXT)
        return result

    def deploy_script(self):
        if not self.local_script.is_file():
            raise OnBoardFrameworkError(
                f"On-board script not found: {self.local_script}"
            )
        deploy = self._run(
            [
                "scp",
                "-o",
                "BatchMode=yes",
                "-o",
                "StrictHostKeyChecking=accept-new",
                str(self.local_script),
                f"{self.target}:{self.remote_script}",
            ],
            "on-board script deploy command",
        )
        if deploy.returncode != 0:
            raise OnBoardFrameworkError(
                f"SCP failed with exit code {deploy.returncode}: {deploy.stderr}"
            )

        chmod = self._run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                "StrictHostKeyChecking=accept-new",
                self.target,
                f"chmod 700 {shlex.quote(self.remote_script)}",
            ],
            "on-board script chmod command",
        )
        if chmod.returncode != 0:
            raise OnBoardFrameworkError(
                f"chmod failed with exit code {chmod.returncode}: {chmod.stderr}"
            )

    def run_case(self, case):
        remote_command = " ".join(
            [
                "/bin/sh",
                shlex.quote(self.remote_script),
                "-t",
                shlex.quote(str(case)),
                "--restore-mode",
                self.restore_mode,
            ]
        )
        run = self._run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                "StrictHostKeyChecking=accept-new",
                self.target,
                remote_command,
            ],
            "on-board test command",
        )
        allure.attach(run.stdout, "DUT test stdout", allure.attachment_type.TEXT)
        allure.attach(run.stderr, "DUT test stderr", allure.attachment_type.TEXT)

        if run.returncode == 255:
            raise OnBoardFrameworkError(
                "SSH transport failed while the DUT state may be unknown"
            )
        result = parse_result(run.stdout, case)
        allure.attach(
            json.dumps(asdict(result), indent=2),
            "parsed MUS result",
            allure.attachment_type.JSON,
        )

        if result.restore == "FAIL" or run.returncode == 3:
            raise OnBoardRestoreError(
                f"DUT restore verification failed for case {case}"
            )
        if run.returncode == 77 or result.test == "SKIP":
            if run.returncode != 77 or result.test != "SKIP":
                raise OnBoardProtocolError(
                    "SKIP result and exit code 77 must be reported together"
                )
            pytest.skip(f"DUT-side case {case} reported SKIP")
        if run.returncode == 1 or result.test == "FAIL":
            if run.returncode != 1 or result.test != "FAIL":
                raise OnBoardProtocolError(
                    "FAIL result and exit code 1 must be reported together"
                )
            pytest.fail(
                f"DUT-side case {case} failed {result.failed} assertion(s)",
                pytrace=False,
            )
        if run.returncode != 0 or result.test != "PASS":
            raise OnBoardFrameworkError(
                f"DUT-side case {case} returned test={result.test}, "
                f"exit_code={run.returncode}"
            )
        return result

    def remove_script(self):
        remove = self._run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                "StrictHostKeyChecking=accept-new",
                self.target,
                f"rm -f {shlex.quote(self.remote_script)}",
            ],
            "on-board script cleanup command",
        )
        if remove.returncode != 0:
            raise OnBoardFrameworkError(
                f"Script cleanup failed with exit code {remove.returncode}: "
                f"{remove.stderr}"
            )

    def replay_command(self, case):
        return (
            f"ssh {self.target} '/bin/sh {self.remote_script} -t {case} "
            f"--restore-mode {self.restore_mode}'"
        )


def _preserved_state_note(runner, state):
    failures = "\n".join(f"- {failure}" for failure in state.failures)
    if not failures:
        failures = "- Framework setup failed before case execution."
    return (
        "The DUT and on-board script were preserved for debugging.\n\n"
        f"Remote script: {runner.remote_script}\n"
        f"Restore mode: {runner.restore_mode}\n"
        f"Replay example: {runner.replay_command('<case-id>')}\n\n"
        f"Recorded failures:\n{failures}"
    )


def on_board_script_fixture(
    *,
    local_script,
    remote_script,
    fixture_name="on_board_script",
):
    """Create a reusable module fixture for one standardized shell script."""

    @pytest.fixture(scope="module", name=fixture_name)
    def _fixture(request, dut_ready):
        state = OnBoardRunState()
        setattr(request.module, "_mus_on_board_run_state", state)
        runner = OnBoardScriptRunner(
            dut_ready.dut1,
            local_script=local_script,
            remote_script=remote_script,
            restore_mode=resolve_restore_mode(request.config),
        )
        continue_on_failure = request.config.getoption("--continue-on-failure")

        def cleanup_on_board_script():
            try:
                preserve = state.framework_failed or (
                    state.failed and not continue_on_failure
                )
                if preserve:
                    with allure.step(
                        "Framework teardown: preserve DUT state after failure"
                    ):
                        allure.attach(
                            _preserved_state_note(runner, state),
                            "DUT state preserved for debugging",
                            allure.attachment_type.TEXT,
                        )
                    return

                with allure.step("Framework teardown: remove on-board script"):
                    runner.remove_script()
            finally:
                if getattr(request.module, "_mus_on_board_run_state", None) is state:
                    delattr(request.module, "_mus_on_board_run_state")

        request.addfinalizer(cleanup_on_board_script)
        with allure.step("Framework setup: deploy shared on-board script"):
            runner.deploy_script()
        return runner

    return _fixture
