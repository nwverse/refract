# Paired native benchmark scenarios

Issue #167 owns these bounded performance references. They compare the same canonical Swift source as ordinary iOS
SwiftUI and actual CLI-generated ArkTS against independently written native code. No benchmark adds a Refract runtime,
generated observer registry or business-logic interpreter. These are settings-shaped screens, not arbitrary SwiftUI.

## Common contract

- 200 immutable-identified rows, title/subtitle typography, native switch accessibility, stable lazy-list identity and
  one immutable row replacement per toggle. The reference does not call the generated row implementation.
- Both variants share only the model, data and scenario driver. The same Release-like native build, input script and
  idle boundaries apply. Generated output is never hand-edited.
- At least 30 iterations for cold start, scroll and local update (eight toggles per update iteration). Preserve native
  process/launch or frame metrics and one distinct platform profiler trace per variant/scenario/iteration.
- Use the existing lower-is-better screening threshold: greater than **5% AND 0.1 ms**, at p50 or p99. Quantiles use
  nearest rank, so p99 is the maximum of 30 samples. This is a screening gate, not permission to accept a reproducible
  regression below the threshold; investigate it with additional measurements instead of raising a baseline.
- Memory is positive integer bytes, never a millisecond value. Installed binary size is reported separately from
  resident memory; neither is silently replaced by a build directory's size.
- `python3 -I bench/common/report.py <run>/manifest.json --output <new-report-directory>` verifies every raw artifact,
  checksum, sample identity and paired metric before producing a report. Synthetic unit-test inputs are not timing
  evidence. No partial report is promoted to PASS.

## Current evidence, not a timing claim

| Platform | What is verified | What remains blocked |
| --- | --- | --- |
| iOS | Xcode 27.2 compiled the canonical Swift screen, independent reference and UI test bundle in Release mode for the simulator SDK and generic iOS SDK. No simulator was created, booted, rebooted or measured. | No executed paired measurements or retained timing traces. The available physical target was unavailable; no physical-device claim is made. |
| HarmonyOS | The real CLI generated `entry/src/main/ets/generated/SettingsScreen.ets` from the same Swift source. A typed app-owned model and separate `@ComponentV2` reference are source-prepared. | No authorized compiler, SDK, `hdc`, signing configuration or execution target. No ArkTS compile, rendering, memory, startup or frame timing claim is made. |

The [iOS harness](ios/README.md), [HarmonyOS source-prepared harness](harmony/README.md) and their exact unexecuted
commands are linked from [the production-readiness matrix](../../docs/production-readiness.md). Compile success,
scenario source, a passing synthetic report test and a manually constructed manifest are not performance evidence.

## Provenance manifest

`bench/common/paired_report.py` defines schema 1. Each run supplies:

1. `environment`: platform, complete source revision, exact acquisition/export commands, Release-like configuration,
   compiler/SDK/profiler versions, target model/OS/architecture and explicit `DEVICE`, `SIMULATOR` or `EMULATOR`.
   `device_result` must agree with the label. A simulator or emulator never closes the physical-device gate.
2. `artifacts`: ordinary raw files below `raw/`, with SHA-256 and exact variant/scenario/iteration ownership. iOS uses
   ZIP-copied `.xcresult` bundles, Xcode `xcresulttool` JSON exports and `.trace` recordings; HarmonyOS uses the
   vendor's native trace and metric exports. A directory merely named `.trace` is not accepted as a trace file.
3. `measurements`: positive finite millisecond samples, one per iteration, directly referencing that iteration's raw
   native metric export and profiler trace. `startupMs` means the native launch-to-first-frame metric; iOS
   `frameIntervalMs` is explicitly a `CADisplayLink` target interval, not CPU frame duration. HarmonyOS uses its
   native frame duration. These metrics are not interchangeable.
4. `resources`: positive integer bytes for resident memory and installed binary size with native artifact provenance.

The report includes the exact commands and limits; raw evidence is retained beside it. Do not commit a report without
its referenced artifacts, redact away their provenance, or use another platform's measurements to fill missing pairs.
