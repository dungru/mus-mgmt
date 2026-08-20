# Wi-Fi functional tests

The human-readable case titles, purposes, and expected results live beside the
pytest implementation in `test_wifi_restart_procfs.py`. The DUT-side POSIX
shell implementation is stored under `on_board_scripts/`, so it can also be
given directly to an RD or customer whose DUT has only a shell environment.
Every script follows the shared `MUS_RESULT_V1` on-board test contract.

## Available test modules

| pytest module | DUT-side script | cases | state-changing cases |
| --- | --- | ---: | --- |
| `test_wifi_restart_procfs.py` | `test_wifi_restart_procfs.sh` | 7 | 2-7 |
| `test_channels_json.py` | `test_channels_json.sh` | 7 | 5-6 |
| `test_rrm_cross_config.py` | `test_rrm_cross_config.sh` | 1 | 1 |
| `test_rrm_interface_downup.py` | `test_rrm_interface_downup.sh` | 1 | 1 |
| `test_interface_downup_during_fwdl.py` | `test_interface_downup_during_fwdl.sh` | 4 | 1-4 |

The RRM cross-configuration test refuses to modify a non-empty neighbor
database. It never uses `dmesg -c`, and it verifies that databases originally
found empty are empty again after the test. The FWDL regression takes a list
and UP/DOWN snapshot of the original Wi-Fi interfaces, recreates the configured
stack with `wifi restart`, then verifies every original interface and state.

## Test lifecycle and failure policy

Before any Wi-Fi case, the framework loads the selected environment, optionally
applies its DUT config bundle, optionally reboots, and verifies SSH plus a DUT
shell command. These actions appear in Allure as **Framework setup**. A setup
error is reported as framework infrastructure failure rather than a Wi-Fi case
failure.

Each Wi-Fi script is copied only once per test module to its own fixed `/tmp`
path. For example, the procfs suite uses:

```text
/tmp/mus-wifi-restart-procfs.sh
```

All selected pytest cases in that module share the script. Each mutating case
snapshots the interface UP/DOWN state and verifies restoration after execution. In a normal
RD run, pytest stops at the first failure and deliberately leaves both the DUT
state and script in place. The Allure teardown attachment shows the remote path
and an SSH replay command. When all selected cases pass, the script is removed.

Run every selected Wi-Fi module directly:

```bash
make test TYPE=functional_tests ENV=dut115 TESTCASE=wifi
```

Run one channels.json case, for example the read-only presence check:

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_channels_json.py OPTS="-k case-1"
```

Run one new module/case with pytest selection, for example FWDL case 1:

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_interface_downup_during_fwdl.py \
  OPTS="-k case-1"
```

Run all seven named Wi-Fi cases (Ethernet management and SSH remain available):

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_wifi_restart_procfs.py
```

Run one named case only:

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_wifi_restart_procfs.py \
  OPTS="--wifi-case 6"
```

Run several selected cases in order:

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_wifi_restart_procfs.py \
  OPTS="--wifi-case 1,3,7"
```

Apply the declared `/etc/config` and `/etc/wireless` bundle, reboot, wait for
SSH, then run the selected cases:

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_wifi_restart_procfs.py \
  OPTS="--apply-dut-config --reboot-after-config"
```

## CI/CD execution

CI should run every selected case even after an individual case fails. Add
`--continue-on-failure`; the final teardown then removes the temporary script
even if the test result is failing. Every case uses restore mode `always`, and
the next case starts only after restore verification succeeds:

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_wifi_restart_procfs.py \
  OPTS="--continue-on-failure"
```

Each Allure result separates framework setup, case execution, and teardown. It
includes configuration details, the one-time SCP/chmod actions, each SSH test
command, parsed `MUS_RESULT_V1`, restore status, and complete DUT stdout/stderr.

## Generate and view the Allure report

The test command writes raw Allure results to `functional_tests/report`. Allure
2.45 limits `allure serve` to localhost previews, so use `allure generate`
when the report must be opened from another computer on the LAN.

From the repository root, generate (or refresh) the static report:

```bash
cd /home/mediatek/Workspace_43/mus-mgmt

allure generate functional_tests/report \
  --output functional_tests/allure-report \
  --clean
```

Serve the generated files on TCP port 31998:

```bash
python3 -m http.server 31998 \
  --bind 0.0.0.0 \
  --directory functional_tests/allure-report
```

Keep that terminal running and open the following URL from a LAN computer:

```text
http://192.168.5.43:31998/
```

If UFW is active, allow only the local `192.168.5.0/24` network:

```bash
sudo ufw allow from 192.168.5.0/24 to any port 31998 proto tcp \
  comment 'Allure Report'
sudo ufw status verbose
```

After each new pytest run, execute the `allure generate ... --clean` command
again to refresh `functional_tests/allure-report`. Stop the web server with
`Ctrl+C`.

## Automatic report generation

`make test` generates `functional_tests/allure-report` automatically after pytest,
including when a test fails. The default is equivalent to `AUTO_REPORT=1`:

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_wifi_restart_procfs.py \
  AUTO_REPORT=1
```

To run pytest without regenerating the static Allure report, set
`AUTO_REPORT=0`:

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_wifi_restart_procfs.py \
  AUTO_REPORT=0
```

`AUTO_REPORT` controls only static report generation. It does not start or
stop the HTTP server.
