# Wi-Fi functional tests

`cases/wifi_restart_procfs.yml` is the test catalogue shown in Allure. It is
the user-facing source of truth: every case has a readable title, purpose and
expected result. The POSIX shell script remains the DUT-side implementation.

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

Apply the declared `/etc/config` and `/etc/wireless` bundle, reboot, wait for
SSH, then run the selected cases:

```bash
make test TYPE=functional_tests ENV=dut115 \
  TESTCASE=wifi/test_wifi_restart_procfs.py \
  OPTS="--apply-dut-config --reboot-after-config"
```

Each Allure result contains the test purpose, expected result, executed SCP and
SSH commands, and the complete stdout/stderr collected from the DUT.

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
