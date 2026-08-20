---
title: DUT Platform Adapters
updated: 2026-08-19
---

# DUT Platform Adapters

Every environment file must declare `dut_system` for each DUT. The suite
creates the correct object through `apis.dut.create_dut()`.

| `dut_system` | Adapter | Connection | Intended use |
|---|---|---|---|
| `openwrt` | `OpenWrtDut` | Ansible `raw` over SSH | OpenWrt without requiring Python on the DUT |
| `buildroot` | `BuildrootDut` | Ansible `raw` over SSH | Buildroot without requiring Python on the DUT |
| `sonic` | Existing `apis.sonic.device.Dut` | Existing CLI, VTYSH, and JSON handler chain | SONiC devices and existing domain objects |

## OpenWrt example

```yaml
topology:
  vars:
    ansible_ssh_user: root
  hosts:
    dut1:
      ansible_host: 192.168.5.115
      vars:
        dut_system: openwrt
```

The `dut115` environment currently uses this configuration. Its smoke test
only runs `echo mus-mgmt-dut-ready`.

## Adding a platform

1. Add an adapter under `apis/dut/`, inherit `BaseDut`, and first provide a
   reliable `shell()` implementation.
2. Add an explicit `dut_system` branch in `apis/dut/factory.py`.
3. Add an environment YAML file and a read-only smoke test.
4. Record capabilities, limitations, and verified versions here, in
   [index.md](index.md), and in [log.md](log.md).

Do not mix product-specific protocol tests into a platform adapter. Product
features belong in their corresponding test suites.
