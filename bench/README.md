# Paired native benchmark scenarios

Issue #167 owns these bounded performance references. They compare the same canonical Swift source as ordinary iOS
SwiftUI and actual CLI-generated ArkTS against independently written native code. No benchmark adds a Refract runtime,
generated observer registry or business-logic interpreter. These are settings-shaped screens, not arbitrary SwiftUI.

## Common contract

- 200 immutable-identified rows, title/subtitle typography, native switch accessibility, stable lazy-list identity and
  one immutable row replacement per toggle. The reference does not call the generated row implementation.
- Both variants share only the model, data and scenario driver. The same Release-like native build, input script and
  idle boundaries apply. Generated output is never hand-edited.
- Exactly the retained traced identities **2...30** for cold start, scroll and local update (eight toggles per update
  iteration). This is a fixed inclusive ID set, not a renumbered replacement for the protocol's 30 acquisitions. Never
  renumber it as 0...29 or fill missing pairs from another source revision. Preserve native process/launch or frame
  metrics and one distinct platform profiler trace per variant/scenario/iteration.
- Use the existing lower-is-better screening threshold: greater than **5% AND 0.1 ms**, at p50 or p99. Quantiles use
  nearest rank, so p99 is the maximum of 30 samples. This is a screening gate, not permission to accept a reproducible
  regression below the threshold; investigate it with additional measurements instead of raising a baseline.
- Memory is positive integer bytes, never a millisecond value. Installed binary size is reported separately from
  resident memory; neither is silently replaced by a build directory's size.
- `python3 -I bench/common/report.py <run>/manifest.json --output <new-report-directory>` verifies every raw artifact,
  checksum, sample identity and paired metric before producing a report. An `xctrace` entry names the archived
  `.trace.zip` file, not the original package directory. Synthetic unit-test inputs are not timing evidence. No partial
  report is promoted to PASS.

## Current evidence, not a timing claim

| Platform | What is verified | What remains blocked |
| --- | --- | --- |
| iOS | Xcode 27.2 compiled the canonical Swift screen, independent reference and UI test bundle in Release mode for the simulator SDK and generic iOS SDK. No simulator was created, booted, rebooted or measured. | No executed paired measurements or retained timing traces. The available physical target was unavailable; no physical-device claim is made. |
| HarmonyOS | The real CLI generated `entry/src/main/ets/generated/SettingsScreen.ets` from the same Swift source. A typed app-owned model and separate `@ComponentV2` reference are source-prepared. | No authorized compiler, SDK, `hdc`, signing configuration or execution target. No ArkTS compile, rendering, memory, startup or frame timing claim is made. |

The [iOS harness](ios/README.md), [HarmonyOS source-prepared harness](harmony/README.md) and their exact unexecuted
commands are linked from [the production-readiness matrix](../../docs/production-readiness.md). Compile success,
scenario source, a passing synthetic report test and a manually constructed manifest are not performance evidence.

## Provenance manifest

`bench/common/paired_report.py` defines schema 2; schema 1 is rejected rather than silently reinterpreted. Each run
supplies:

1. `environment`: platform, complete source revision, the retained build-provenance path and SHA-256, exact
   acquisition/export commands, Release-like configuration, compiler/SDK/profiler versions, target
   model/OS/architecture and explicit `DEVICE`, `SIMULATOR` or `EMULATOR`. `device_result` must agree with the label.
   A simulator or emulator never closes the physical-device gate.
2. `artifacts`: ordinary raw files below `raw/`, with SHA-256, source revision, shared build-provenance SHA-256,
   an explicit `timing`/`profiler`/`memory`/`binary`/`build-provenance` role, and exact variant/scenario/iteration
   ownership. The build manifest is shared by both variants and therefore has `variant=shared`, `scenario=build` and
   sentinel iteration 2; it is not an iteration-2 timing sample. Every other artifact and measurement must match the
   environment's revision and build hash. No evidence can be copied into another revision or build. The reporter parses
   the retained build JSON and requires its own `source_revision` and configuration to match, plus distinct nonempty
   generated/reference product file identities. Manifest declarations alone are not build provenance. iOS uses
   ZIP-copied `.xcresult` bundles, Xcode `xcresulttool` JSON exports and archived `.trace.zip` packages; HarmonyOS
   uses the vendor's native trace and metric exports. A directory merely named `.trace` is not accepted as a trace file.
   `bench/ios/archive_trace.py` preserves an already recorded Instruments package without replacing existing evidence;
   it does not run a profiler or establish native provenance.
3. `measurements`: one positive finite `value` in milliseconds for every exact variant/scenario/iteration, with a
   declared native `definition`, directly referencing identity-matched raw metric evidence and a profiler trace.
   `startupMs` is an `XCTApplicationLaunchMetric` duration on iOS or a separately identified native
   launch-to-first-frame duration on HarmonyOS. iOS reads the retained native `durationMs` measurement, either directly
   with its canonical `nativeMeasurementSha256` or from a `measurements` array with an index/checksum selector. The
   selected native object must carry the same revision, variant, scenario and iteration; a manifest-only `value` or an
   unrelated first-display timestamp cannot supply it. HarmonyOS reads native `launchStartTimestamp` and
   `firstFrameTimestamp` from the artifact and subtracts them in milliseconds; it does not accept manifest-supplied
   timestamps. A first-frame timestamp alone is not a launch duration. iOS startup requires that iteration's
   `metrics.json`; `firstDisplay` is a monotonic scene-activation timestamp, **not a launch duration**. iOS
   `frameIntervalMs` reads `native-samples.json` itself, including `sourceRevision`, variant/scenario/iteration,
   `session`, matching `native_pid`, `completedIterations=1`, `recordedIteration`, `iterationByFrame` and its
   `CADisplayLink` `targetTimestamp - timestamp` array. The reporter recalculates the per-iteration nearest-rank p99
   from that raw array and requires the manifest `value` to match; it never trusts a manifest `source_samples` array.
   The array is not itself a scalar and its intervals are not CPU frame duration. HarmonyOS uses its own native frame
   duration with the same explicit reduction requirement. These metrics are not interchangeable; the outer comparisons
   still use nearest-rank p50/p99 across the retained iteration scalars.
4. `resources`: positive integer bytes. Every scroll/state-update iteration requires a generated/reference
   `residentMemoryBytes` pair with `memory`-role provenance at that same identity. Exactly one generated and one
   reference `installedBinaryBytes` measurement is required for one scenario, with `binary`-role provenance; these
   describe the installed product at the shared build identity, not per-iteration timing. Resource provenance must
   match the environment's revision and build hash. The report emits paired values and generated-minus-reference
   deltas alongside the raw entries. Each resource JSON carries its own `sourceRevision`, variant/scenario/iteration,
   `metric`, `unit=bytes` and `bytes`; memory also carries the observed `pid`, matching `native_pid`. The reporter
   requires the exported bytes to equal the declared resource bytes. The existing regression thresholds apply to timing
   only, not resource bytes.

The report includes the exact commands and limits; raw evidence is retained beside it. Do not commit a report without
its referenced artifacts, redact away their provenance, or use another platform's measurements to fill missing pairs.
