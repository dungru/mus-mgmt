---
title: Framework Overview
updated: 2026-08-19
---

# Framework Overview

`mus-mgmt` is the MUS Team hardware automation framework. It retains reusable
automation infrastructure while treating DUT operating systems as explicit
platform choices instead of assuming every device runs SONiC.

## Current structure

```text
apis/              # Shared connection, DUT, packet, and traffic-generator APIs
apis/dut/          # Platform-neutral DUT adapter factory
apis/sonic/        # Retained SONiC-specific capabilities
smoke_tests/       # Minimal non-destructive connection validation
functional_tests/  # Functional validations, including OpenWrt Wi-Fi cases
protocol_tests/    # Retained as an existing test-design reference
sdk_tests/         # Retained as a fixture and case-design reference
docs/              # Maintained project wiki
```

`clx_diag_tests/` and `kis_tests/` were removed because they are outside the
current MUS test scope.

## Design principles

1. **Platform neutrality:** select adapters through the YAML `dut_system` value.
2. **Safe onboarding:** begin with read-only or non-destructive smoke tests.
3. **Environment separation:** keep connection data in environment YAML files;
   do not hard-code laboratory topology in test logic.
4. **Portable DUT artifacts:** DUT-side test scripts must run with POSIX `sh`.
5. **Observable execution:** attach actions, stdout, and stderr to Allure.
6. **Deferred external integration:** do not initialize traffic-generator
   resources until their control interface and locking rules are known.

## Current limitations and next steps

- OpenWrt is the only physically verified DUT platform so far.
- Buildroot and SONiC environments still need physical validation.
- SONiC legacy gRPC/protobuf compatibility requires separate validation.
- Traffic-generator APIs, ports, and resource locks remain undecided.

See [DUT platform adapters](dut-platforms.md), [usage](usage.md), and the
[change log](log.md).
