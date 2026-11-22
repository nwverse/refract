# iOS generated-versus-native reference harness

## Verified boundary

`RefractBench.xcodeproj` directly references `../android/SettingsScreen.swift`. That exact canonical source supplies
`SettingsScreen` and `GeneratedSettingRow`; it is not copied into a new iOS-only screen. `ReferenceSettingsScreen.swift`
is an independently written ordinary SwiftUI implementation. Both consume the same 200-row `ObservableObject` model
and typed protocol adapter. The model uses `@preconcurrency SettingsModel` only to satisfy the canonical protocol's
unannotated isolation on the main actor; Swift strict concurrency remains enabled.

Xcode 27.2 / iOS 27.2 SDK successfully compiled both Release `build-for-testing` destinations:

```sh
DERIVED_DATA=<new-output-directory> bench/ios/build.sh
# Equivalent physical-SDK compile-only check, no attached device or execution:
xcodebuild -project bench/ios/RefractBench.xcodeproj -scheme RefractBench \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath <new-output-directory> CODE_SIGNING_ALLOWED=NO build-for-testing
```

This is native compiler evidence only. No simulator was created, started, restarted, used or stopped. No application
was installed. There are no timing, rendering, memory or physical-device results in this change.

`build.sh` requires a clean committed checkout before and after compilation. It writes an immutable
`refract-build-provenance.json` in DerivedData with the exact source revision, original xctestrun SHA-256 and the
app/UI-test bundle file identities. The trace runner requires this manifest and rechecks every listed file before
launch. Do not pair a checkout at one revision with products built from another, reuse a generic-device build or
reuse products without their manifest; rebuild in a new DerivedData directory instead.

## Scenario construction

The generated and reference screens have the same explicit `.plain` list style, title/subtitle typography, switch
accessibility labels and stable `Identifiable` rows. `BenchmarkScrollDriver` wraps both hosts in the same
`ScrollViewReader`; a shared native task issues identical programmatic scrolls. Local update performs eight toggles
per iteration through the same model. Thirty iterations are required for each of cold start, scroll and state update.

`XCTApplicationLaunchMetric` supplies launch samples from the platform's performance test infrastructure. The
`CADisplayLink` helper records the native `targetTimestamp - timestamp` interval during the two other scenarios.
It is **not** CPU frame duration and must not be relabelled as such. The completion marker is hidden native text that
reports the actual number of completed iterations; the UI test cannot pass by waiting on the initial screen alone.
The helper stores source revision, variant, scenario and per-frame iteration with its raw samples. The XCUITest target
is not part of the app runtime, and the helper adds no Refract library.

## Running without touching shared targets

The run driver accepts only an explicitly owned, already-booted target. It never creates, boots, reboots, erases,
pairs or selects `booted`. The current available physical target was not usable, and no owned timing simulator was
available to this issue, so these execution commands were **not run**:

```sh
# First coordinate exclusive ownership. Pass that owner's already-booted UDID;
# do not use another issue's device or create a simulator from this script.
TARGET_UDID=<owned-udid> DERIVED_DATA=<new-output-directory> \
  RUN_DIRECTORY=<new-run-directory> bench/ios/run.sh

# Native metric export; retain these files with the raw .xcresult bundle.
xcrun xcresulttool get test-results summary --path <run>/results.xcresult --format json > <run>/summary.json
xcrun xcresulttool get test-results metrics --path <run>/results.xcresult --format json > <run>/metrics.json

# Record exactly one profiler package per variant/scenario/iteration.
# This driver obtains the actual PID from XCUIApplication, waits for explicit
# Instruments readiness before releasing the native script, checks native
# completion, gracefully stops xctrace, and preserves its package. Repeat this
# command for every variant, scroll/stateUpdate scenario, and iteration 0...29;
# use a new run directory each time. It never creates, boots or reboots a target.
# --window bounds deferred work, not the measured iteration window.
python3 -I bench/ios/iteration_trace_runner.py \
  --target-udid <owned-udid> --derived-data <build-output-directory> \
  --variant <generated-or-reference> --scenario <scroll-or-stateUpdate> \
  --iteration <0-through-29> --source-revision <clean-committed-revision> \
  --run-directory <new-iteration-run-directory>

Each iteration writes a uniquely named final xctestrun beside the original in `Build/Products`, preserving
`__TESTROOT__` resolution without modifying that original. The run directory retains an identical
`iteration-trace-config.xctestrun`, the build manifest and `iteration-trace-config.json`. The receipt separately
records the configuration SHA-256, build-manifest SHA-256, source revision, control directory and iteration. The
runner reads back the final hosted-test environment and refuses to replace an existing configuration or receipt.

# Equivalent lower-level recorder command used by the driver after the app
# publishes its PID. Do not use a filename as a substitute for the handshake:
xcrun xctrace record --device <owned-udid> --template 'Animation Hitches' \
  --attach <observed-running-app-pid> --window <bounded-deferred-work-window> \
  --output <new-iteration-run>/<variant>-<scenario>-<iteration>.trace

# The driver archives only after xctrace exits successfully, emits exact raw
# identity, bytes and SHA-256, and retains the handshake and recorder logs.
# xctrace writes a package directory; the reporter requires an ordinary raw file.
# Archive only after recording finishes. Repeat for every exact iteration and do
# not infer identity from the filename. This emits byte count and SHA-256 for the
# manifest, rejects links and never replaces an existing archive.
python3 -I bench/ios/archive_trace.py \
  <new-run>/raw/<variant>-<scenario>-<iteration>.trace \
  --output <new-run>/raw/<variant>-<scenario>-<iteration>.trace.zip

# Preserve the native result bundle as an ordinary ZIP for independent review.
ditto -c -k --keepParent <run>/results.xcresult <run>/raw/results.xcresult.zip
python3 -I bench/common/report.py <run>/manifest.json --output <new-report-directory>
```

`run.sh` is an intentionally conservative initial driver and currently selects the simulator destination. Its read-only
probe rejects unavailable or not-booted targets. Before any physical measurement, add an explicit `devicectl`
availability/identity probe and the `platform=iOS,id=<udid>` destination; do not infer physical availability from a
`generic/platform=iOS` compile. A generic device compile is not a device result.

The per-iteration driver uses a new control directory for each app launch. The UI test publishes the actual
`XCUIApplication.processIdentifier` and exact variant/scenario/iteration, then waits for the app to observe the
runner's recorder-ready file. Only then does it tap the start boundary. The native script executes the same single
scroll destination or eight state updates as its corresponding iteration in the original 30-iteration task. It
publishes `complete 1` through the existing accessibility boundary while raw samples retain the original iteration
number. The runner rejects missing, stale, duplicate or mismatched PID/readiness/completion packets, sends SIGINT
only to its own `xctrace` child, waits for successful package completion, and archives before releasing the UI test.
No shell duration is substituted for a native metric.

Run the control-plane and source-wiring tests with:

```sh
python3 -I bench/ios/iteration_trace_runner_test.py -v
python3 -I bench/ios/iteration_trace_source_test.py -v
python3 -I bench/ios/archive_trace_test.py -v
```

These use synthetic processes and packages, not Instruments or timing evidence. In this change they were executed on
Linux; no Xcode/SwiftUI compile, XCTest execution, Instruments readiness behavior or trace acquisition was verified
on macOS. The native driver requires an authorized macOS toolchain and an explicitly owned, already-running target.
The original cold-start test still uses 30 `XCTApplicationLaunchMetric` iterations. The original non-traced scenario
entry points remain available but the complete 30-iteration traced collection must use the new per-launch driver.
Simulator results, if collected later, must remain explicitly labelled and cannot close the physical-device gate.
The app helper persists raw display samples in its own defaults store. Retrieval must still use `devicectl` or the
explicit simulator's data container and preserve the raw JSON before report generation. Until native collection is
run and inspected, this is a **synthetically tested capture protocol**, not a completed paired measurement.

## Regression and evidence policy

Use `bench/common/report.py`. It requires 30 pairs of samples for each scenario, one native profiler trace per
iteration, exact source/toolchain/target provenance, finite millisecond samples and SHA-256 verification. It does not
accept a median as p99 or a trace reused across iterations. `CADisplayLink` intervals and Xcode launch metrics are
reported as distinct native definitions; shell elapsed time is never substituted. Keep installed binary bytes and
resident memory bytes separate. The physical-device gate remains open even after a labelled simulator result.
