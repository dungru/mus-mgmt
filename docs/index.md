---
title: MUS Management Automation Wiki
updated: 2026-08-19
---

# MUS Management Automation Wiki

This directory is the maintained knowledge base for the MUS Team automation
framework. Update the relevant topic and [log.md](log.md) whenever new
information is added.

## Getting started

- [Usage](usage.md): run smoke and functional tests and view Allure reports.
- [Adding an on-board test](adding-on-board-test.md): shell contract, restore policy, and templates.
- [Framework overview](overview.md): component responsibilities and boundaries.
- [DUT platform adapters](dut-platforms.md): SONiC, OpenWrt, and Buildroot connections.

## Maintenance and decisions

- [Wiki maintenance schema](wiki-schema.md): document structure and update workflow.
- [Change log](log.md): completed work and pending decisions.
- [Raw evidence](raw/README.md): immutable requirements, device data, and external files.

## Imported historical references

- [programming_guide.md](programming_guide.md): legacy commit and coding guidance.
- [reference.md](reference.md): maintained external references.

## Current facts

- Controller workspace: `/home/mediatek/Workspace_43/mus-mgmt`
- Initial DUT: `root@192.168.5.115`, OpenWrt 21.02-SNAPSHOT on `mediatek/mt7986`
- Traffic generator: control interface is still undecided
- Initial validation: `smoke_tests/smoke/test_dut_connection.py`
- Wi-Fi validation: `functional_tests/wifi/test_wifi_restart_procfs.py`
