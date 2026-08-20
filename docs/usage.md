---
title: Running MUS Tests
updated: 2026-08-19
---

# Usage

## Controller workspace

```bash
ssh mediatek@192.168.5.43
cd /home/mediatek/Workspace_43/mus-mgmt
```

The Makefile automatically uses the repository `.venv/bin/python`; no absolute
`PY` argument is required.

## Run the OpenWrt smoke test

```bash
make test TYPE=smoke_tests ENV=dut115 \
  TESTCASE=smoke/test_dut_connection.py
```

Expected result: `1 passed`. The test uses Ansible raw SSH to run
`echo mus-mgmt-dut-ready` on `root@192.168.5.115` without changing DUT state.

## Run Wi-Fi functional tests

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_wifi_restart_procfs.py
```

Run one case with `OPTS="--wifi-case 6"`. Apply the declared DUT bundle and
reboot first with `OPTS="--apply-dut-config --reboot-after-config"`.

The shared OpenWrt configuration bundle for the current DUT environment is
stored at `openwrt_setting/dut15/` (`config/` maps to `/etc/config`; `wireless/`
maps to `/etc/wireless`). Both smoke and functional suites use this same bundle.

## Generate and publish the Allure report

```bash
allure generate functional_tests/report --output functional_tests/allure-report --clean
python3 -m http.server 31998 --bind 0.0.0.0 \
  --directory functional_tests/allure-report
```

Open `http://192.168.5.43:31998/`. If UFW is active, allow the LAN only:

```bash
sudo ufw allow from 192.168.5.0/24 to any port 31998 proto tcp \
  comment 'Allure Report'
```

## Add an environment

1. Add `<environment>.yml` under the suite's `environments/` directory.
2. Set `ansible_host` and `vars.dut_system` for every host.
3. Run the platform connection smoke test first.
4. Record verified behavior in [log.md](log.md) and update
   [DUT platform adapters](dut-platforms.md).

## Troubleshooting

- `No module named pytest`: verify that `.venv/bin/python` exists.
- Environment file not found: verify `ENV` and the suite environment path.
- SSH failure: run `ssh root@<DUT-IP> 'echo ready'` from the controller.
- Do not install Python on OpenWrt or Buildroot DUTs; their adapters use
  Ansible `raw` specifically to support minimal systems.
