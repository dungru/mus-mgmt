"""Transport an RD-owned POSIX shell test to a DUT and attach its evidence."""

import shlex
import subprocess
from pathlib import Path

import allure


class WifiScriptRunner:
    def __init__(self, dut):
        self.dut = dut
        self.user = dut._adhoc.group_vars.get("ansible_ssh_user", "root")

    def _run(self, command):
        result = subprocess.run(command, capture_output=True, text=True)
        record = "$ " + shlex.join(command) + "\n"
        record += "exit_code=" + str(result.returncode) + "\n"
        record += "--- stdout ---\n" + result.stdout
        record += "\n--- stderr ---\n" + result.stderr
        allure.attach(record, "transport command", allure.attachment_type.TEXT)
        return result

    def run_procfs_case(self, case):
        script = Path(__file__).parent / "scripts" / "test_wifi_restart_procfs.sh"
        remote = "/tmp/mus-test_wifi_restart_procfs.sh"
        target = f"{self.user}@{self.dut.ipaddr}"

        with allure.step("Deploy Wi-Fi shell script to DUT via SCP"):
            deploy = self._run([
                "scp", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
                str(script), f"{target}:{remote}",
            ])
            assert deploy.returncode == 0, deploy.stderr

        with allure.step(f"Run Wi-Fi procfs case {case} on DUT"):
            test_args = ["-a"] if case == "all" else ["-t", case]
            run = self._run([
                "ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
                target, " ".join([f"chmod 700 {remote} && /bin/sh {remote}", *test_args]),
            ])
            allure.attach(run.stdout, "DUT test stdout", allure.attachment_type.TEXT)
            allure.attach(run.stderr, "DUT test stderr", allure.attachment_type.TEXT)
            assert run.returncode == 0, run.stdout + "\n" + run.stderr
