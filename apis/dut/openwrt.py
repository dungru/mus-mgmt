"""DUT adapter for OpenWrt targets."""

import shlex
import socket
import subprocess
import tarfile
import tempfile
import time
import uuid
from pathlib import Path

from .base import BaseDut


class OpenWrtDut(BaseDut):
    system = "openwrt"

    def release(self):
        """Return the OpenWrt release metadata without changing the DUT."""
        values = {}
        for line in self.shell("cat /etc/openwrt_release").splitlines():
            key, separator, value = line.partition("=")
            if separator:
                values[key] = value.strip("'")
        return values

    def reboot(self):
        """Schedule a reboot after returning the SSH response to the runner."""
        self.shell("nohup sh -c 'sleep 1; reboot' >/dev/null 2>&1 &")

    def wait_for_ssh(self, timeout=120, interval=3):
        """Wait until SSH is accepting connections after a planned reboot."""
        deadline = time.monotonic() + timeout
        last_error = None
        while time.monotonic() < deadline:
            try:
                with socket.create_connection((self.ipaddr, 22), timeout=5):
                    return
            except OSError as error:
                last_error = error
                time.sleep(interval)
        raise TimeoutError(
            f"Timed out waiting {timeout}s for SSH on {self.name} ({self.ipaddr}): "
            f"{last_error}"
        )

    def apply_config_bundle(self, bundle_root, mappings):
        """Back up then replace configured DUT directories from a local bundle.

        This method is intentionally invoked only by the explicit
        ``--apply-dut-config`` pytest option.  It does not reboot the DUT;
        the caller decides whether a reboot is appropriate for the bundle.
        """
        bundle_root = Path(bundle_root).resolve()
        items = []
        for mapping in mappings:
            source = Path(mapping["source"])
            destination = Path(mapping["destination"])
            if source.is_absolute() or ".." in source.parts:
                raise ValueError(f"Invalid config source: {source}")
            if not str(destination).startswith("/etc/"):
                raise ValueError(f"Config destination must be under /etc: {destination}")
            local_source = (bundle_root / source).resolve()
            if not local_source.is_relative_to(bundle_root) or not local_source.is_dir():
                raise ValueError(f"Config directory not found: {local_source}")
            items.append((source, destination, local_source))

        token = uuid.uuid4().hex
        remote_archive = f"/tmp/mus-config-{token}.tar.gz"
        remote_stage = f"/tmp/mus-config-{token}"
        backup_root = f"/tmp/mus-backup-{token}"
        with tempfile.NamedTemporaryFile(suffix=".tar.gz") as archive:
            with tarfile.open(archive.name, "w:gz") as tar:
                for source, _, local_source in items:
                    tar.add(local_source, arcname=str(source))

            username = self._adhoc.group_vars.get("ansible_ssh_user", "root")
            subprocess.run(
                [
                    "scp", "-o", "BatchMode=yes", "-o",
                    "StrictHostKeyChecking=accept-new", archive.name,
                    f"{username}@{self.ipaddr}:{remote_archive}",
                ],
                check=True,
            )

        commands = [
            "set -eu",
            f"mkdir -p {shlex.quote(remote_stage)} {shlex.quote(backup_root)}",
            f"tar -xzf {shlex.quote(remote_archive)} -C {shlex.quote(remote_stage)}",
        ]
        for source, destination, _ in items:
            backup = Path(backup_root, str(destination).lstrip("/"))
            commands.extend(
                [
                    f"mkdir -p {shlex.quote(str(backup.parent))}",
                    f"[ ! -e {shlex.quote(str(destination))} ] || cp -a {shlex.quote(str(destination))} {shlex.quote(str(backup))}",
                    f"rm -rf {shlex.quote(str(destination))}",
                    f"mkdir -p {shlex.quote(str(destination))}",
                    f"tar -C {shlex.quote(str(Path(remote_stage, source)))} -cf - . | tar -C {shlex.quote(str(destination))} -xf -",
                ]
            )
        commands.extend(
            [
                f"rm -rf {shlex.quote(remote_stage)} {shlex.quote(remote_archive)}",
            ]
        )
        self.shell("; ".join(commands))
        return backup_root
