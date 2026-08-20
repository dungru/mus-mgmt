"""Common SSH/Ansible DUT operations shared by non-SONiC targets."""


class DutConnectionError(RuntimeError):
    """Raised when a command cannot be executed on a DUT."""


class BaseDut:
    """Minimal platform-neutral DUT connection.

    OpenWrt and Buildroot usually do not ship Python, so commands use
    Ansible's ``raw`` module rather than the Python-dependent ``shell`` module.
    """

    system = "generic"

    def __init__(self, adhoc, host):
        self._adhoc = adhoc
        self.name = host.name
        self.ipaddr = host.vars["ansible_host"]
        self.vars = host.vars.get("vars", {})

    def shell(self, command, **kwargs):
        result = self._adhoc.run([self.name], "raw", command, **kwargs)
        host_result = result[self.name]

        if host_result.failed:
            raise DutConnectionError(
                f"Command failed on {self.name} ({self.ipaddr})\n"
                f"command: {command}\n"
                f"stdout: {host_result.get('stdout', '')}\n"
                f"stderr: {host_result.get('stderr', '')}"
            )

        return host_result.get("stdout", "").strip()
