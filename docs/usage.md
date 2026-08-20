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

The default interactive behavior stops after the first framework or case
failure and preserves the DUT state plus `/tmp/mus-wifi-restart-procfs.sh` for
debugging. The Allure teardown attachment includes a replay command. For CI/CD,
continue through all selected cases and clean the temporary script at the end:

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_wifi_restart_procfs.py \
  OPTS="--continue-on-failure"
```

`--wifi-case` accepts `all`, one case number, or a comma-separated list such as
`1,3,7`.

Every selected case executes directly. The DUT-side script snapshots and
restores the runtime state changed by the case:

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_wifi_restart_procfs.py \
  OPTS="--wifi-case all"
```

On-board shell tests follow `MUS_RESULT_V1`. Interactive runs use
`--restore-mode=on-success`; CI continuation uses `always`. An explicit
`--restore-mode=never` is available for debugging but cannot be combined with
`--continue-on-failure`. See [Adding an on-board test](adding-on-board-test.md)
for the reusable shell and pytest templates.

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
- A Wi-Fi failure intentionally leaves the shared script on the DUT in a
  normal run; use its Allure replay command or remove
  `/tmp/mus-wifi-restart-procfs.sh` after investigation.
- Do not install Python on OpenWrt or Buildroot DUTs; their adapters use
  Ansible `raw` specifically to support minimal systems.
