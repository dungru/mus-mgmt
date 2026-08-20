---
title: MUS Automation Wiki Log
---

# Wiki Change Log

This is an append-only record. Use a consistent date and category prefix for
every entry.

## [2026-08-19] bootstrap | MUS framework and documentation wiki

- Created an independent `mus-mgmt` automation base without importing
  uncommitted source changes.
- Removed `clx_diag_tests/` and `kis_tests/`; created `smoke_tests/` as the
  minimal validation suite.
- Added DUT adapter selection for `sonic`, `openwrt`, and `buildroot`.
- Confirmed `root@192.168.5.115` as OpenWrt 21.02-SNAPSHOT on
  `mediatek/mt7986` and passed a non-destructive SSH smoke test.
- Created the project virtual environment and pytest/Ansible dependencies.
- Added Wi-Fi shell-script automation with Allure evidence collection.
- Traffic-generator control remains undecided.
