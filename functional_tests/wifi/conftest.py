"""Fixtures and safe provisioning controls for Wi-Fi tests."""

from pathlib import Path

import pytest

from apis.dut import create_dut
from apis.utils import AttrDict


pytest_plugins = ["apis.fixtures"]


def pytest_configure(config):
    config.addinivalue_line("markers", "wifi_restart: Wi-Fi restart/procfs test")
    config.addinivalue_line("markers", "disruptive: changes Wi-Fi interface state")


@pytest.fixture(scope="session")
def topo(request, monkeypatch_session, adhoc):
    handler_chain = request.config.getoption("--handler_chain").upper().split(",")
    result = AttrDict()
    for host in adhoc.hosts:
        system = host.vars.get("vars", {}).get("dut_system")
        if system is None:
            raise pytest.UsageError(f"{host.name} must declare dut_system")
        result[host.name] = create_dut(adhoc, host, system, handler_chain)
    yield result


@pytest.fixture(scope="session", autouse=True)
def provision_dut(request, topo):
    """Optionally SCP a bundle, reboot, and verify SSH before Wi-Fi tests."""
    if not request.config.getoption("--apply-dut-config"):
        yield
        return

    environment_root = Path(request.config.invocation_params.dir, "environments")
    for dut in topo.values():
        config = dut.vars.get("dut_config")
        if config is None:
            continue
        bundle_root = (environment_root / config["folder"]).resolve()
        dut.apply_config_bundle(bundle_root, config["mappings"])
        if request.config.getoption("--reboot-after-config"):
            dut.reboot()
            dut.wait_for_ssh(request.config.getoption("--ssh-health-timeout"))
        assert dut.shell("echo mus-mgmt-config-ready") == "mus-mgmt-config-ready"
    yield


def pytest_addoption(parser):
    parser.addoption("--environment", action="store", default="dut115")
    parser.addoption("--apply-dut-config", action="store_true")
    parser.addoption("--reboot-after-config", action="store_true",
                     help="Reboot and wait for SSH after applying the config bundle")
    parser.addoption("--ssh-health-timeout", type=int, default=120)
    parser.addoption("--wifi-case", action="store", default="all",
                     help="Procfs case number (1-7), or 'all' (default)")
    parser.addoption("--handler_chain", action="store", default="cli,vtysh,json")
