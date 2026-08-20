# MUS Management Automation

`mus-mgmt` is the MUS Team automation framework for hardware DUT validation.
It runs on an Ubuntu controller and supports OpenWrt, Buildroot, and SONiC
targets through platform adapters.

## Quick start

Run the OpenWrt connectivity smoke test:

```bash
make test TYPE=smoke_tests ENV=dut115 \
  TESTCASE=smoke/test_dut_connection.py
```

Run the Wi-Fi functional suite:

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_wifi_restart_procfs.py
```

The framework uses the repository `.venv` automatically when available. Test
results are written to `functional_tests/report` and the static Allure report
is generated at `functional_tests/allure-report`.

## Repository layout

```text
apis/                 Platform-neutral DUT and transport adapters
smoke_tests/          Safe connectivity checks
functional_tests/     Human-readable functional validation suites
openwrt_setting/      Shared OpenWrt configuration bundles
docs/                 Usage, platform, and maintenance documentation
```

## Documentation

Start with [docs/usage.md](docs/usage.md) for controller setup, test commands,
configuration application, and Allure reporting.
