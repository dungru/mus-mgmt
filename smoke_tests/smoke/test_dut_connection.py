"""Safe first test for a newly imported DUT environment."""

import pytest


@pytest.mark.dut_connection
def test_dut_accepts_shell_command(topo):
    assert topo.dut1.system == "openwrt"
    assert topo.dut1.shell("echo mus-mgmt-dut-ready") == "mus-mgmt-dut-ready"
