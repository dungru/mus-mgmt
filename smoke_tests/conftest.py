"""Shared fixtures for the MUS hardware automation suite."""

from pathlib import Path

import pytest

from apis.dut import create_dut
from apis.utils import AttrDict


pytest_plugins = ["apis.fixtures"]


def pytest_configure(config):
    config.addinivalue_line(
        "markers", "dut_connection: basic non-destructive DUT connectivity"
    )


@pytest.fixture(scope="session")
def topo(request, monkeypatch_session, adhoc):
    """Create DUT objects without SDK, reset, or traffic-generator setup."""
    handler_chain = request.config.getoption("--handler_chain").upper().split(",")
    topo = AttrDict()

    for host in adhoc.hosts:
        system = host.vars.get("vars", {}).get("dut_system")
        if system is None:
            raise pytest.UsageError(
                f"{host.name} must declare dut_system in its environment YAML"
            )
        topo[host.name] = create_dut(adhoc, host, system, handler_chain)

    yield topo


@pytest.fixture(scope="session", autouse=True)
def apply_dut_config(request, topo):
    """Apply a declared config bundle only when explicitly requested."""
    if not request.config.getoption("--apply-dut-config"):
        yield
        return

    environment_root = Path(request.config.invocation_params.dir, "environments")
    for dut in topo.values():
        config = dut.vars.get("dut_config")
        if config is None:
            continue
        if not hasattr(dut, "apply_config_bundle"):
            raise pytest.UsageError(
                f"{dut.name} ({dut.system}) does not support config bundles"
            )
        bundle_root = environment_root / config["folder"]
        dut.apply_config_bundle(bundle_root, config["mappings"])
        assert dut.shell("echo mus-mgmt-config-ready") == "mus-mgmt-config-ready"
    yield


def pytest_addoption(parser):
    parser.addoption(
        "--environment",
        action="store",
        default="dut115",
        help="Environment file in mus_tests/environments (default: %(default)s)",
    )
    parser.addoption(
        "--apply-dut-config",
        action="store_true",
        help="Back up and apply dut_config mappings declared by the environment YAML",
    )
    parser.addoption(
        "--handler_chain",
        action="store",
        default="cli,vtysh,json",
        help="DUT command handlers, comma-separated (default: %(default)s)",
    )
