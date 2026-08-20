"""Create a DUT adapter from the environment inventory."""

from .buildroot import BuildrootDut
from .openwrt import OpenWrtDut


def create_dut(adhoc, host, system, handler_chain=()):
    """Create the platform adapter declared by ``dut_system`` in YAML."""
    system = system.lower()

    if system == "sonic":
        # SONiC's generated gRPC bindings are legacy dependencies. Import them
        # only when a SONiC target is actually requested.
        from apis.sonic.device import Dut as SonicDut

        return SonicDut(adhoc, host, handler_chain)
    if system == "openwrt":
        return OpenWrtDut(adhoc, host)
    if system == "buildroot":
        return BuildrootDut(adhoc, host)

    raise ValueError(
        f"Unsupported dut_system={system!r} for {host.name}. "
        "Supported values: sonic, openwrt, buildroot"
    )
