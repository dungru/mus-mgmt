# MUS minimal automation suite

This is the starting point for the MUS team test framework. It deliberately
uses the existing `apis` fixture and a platform-neutral DUT adapter, while
omitting SDK setup, DUT reset, and traffic-generator control. The supported
YAML values for `dut_system` are `sonic`, `openwrt`, and `buildroot`.

Current environment: `dut115` (`root@192.168.5.115`). The current DUT exposes
a minimal shell rather than a detectable SONiC installation, so the first
smoke test is intentionally limited to a non-destructive shell command.

Run from the repository root:

```bash
make test TYPE=smoke_tests ENV=dut115 TESTCASE=smoke/test_dut_connection.py
```

Before adding port, protocol, or traffic tests, replace the bootstrap
SONiC requires its existing board metadata and command handler chain. OpenWrt
and Buildroot use Ansible `raw` commands so they do not require Python on the
DUT. Traffic generator configuration is intentionally absent until its control
interface is decided.
