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

This is native compiler evidence only. The physical-SDK destination does not attach, sign or measure a device.
Per-iteration simulator execution, when separately coordinated, is documented below and is not a device result.

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
The helper stores source revision, variant, scenario and per-frame iteration with its raw samples. For a traced scroll
or state-update iteration, `completeIteration` establishes the final recorder state before the app embeds one immutable
`finalSamples` packet in `native-completion.json`. The packet carries the exact revision, variant, scenario, selected
iteration and native PID, `completedIterations == 1`, `recordedIteration == selectedIteration`, and equally sized frame
interval/tag arrays whose every tag names the selected iteration. Both XCTest and the runner reject missing, partial,
duplicate, stale or mismatched packets, empty or unbounded arrays, and non-finite or non-positive display intervals
before completion or archive acceptance. The runner persists this packet directly as `raw/native-samples.json` and
binds its path and SHA-256 in `raw/iteration-trace.json`; finalizers consume that durable file, not preferences.

`UserDefaults` is diagnostic only. Its asynchronous plist can still contain a periodic snapshot with
`completedIterations == 0` after native completion; no sleep, polling or `UserDefaults.synchronize()` can turn it into
the completion channel. A stale diagnostic plist never overrides a valid final completion packet. The separate startup
packet retains its exact `firstDisplay` timestamp, and the 30-iteration cold-start metric remains unchanged.
The XCUITest target is not part of the app runtime, and the helper adds no Refract library.

## Running without touching shared targets

The run driver accepts only an explicitly owned, already-booted target. It never creates, boots, reboots, erases,
pairs or selects `booted`. The current physical target was unavailable. Execution remains conditional on a
maintainer-coordinated simulator; no generic SDK compile or source inspection supplies target ownership:

```sh
# First coordinate exclusive ownership. Pass that owner's already-booted UDID;
# do not use another issue's device or create a simulator from this script.
TARGET_UDID=<owned-udid> DERIVED_DATA=<new-output-directory> \
  RUN_DIRECTORY=<new-run-directory> bench/ios/run.sh

# Native metric export; retain these files with the raw .xcresult bundle.
xcrun xcresulttool get test-results summary --path <run>/results.xcresult --format json > <run>/summary.json
xcrun xcresulttool get test-results metrics --path <run>/results.xcresult --format json > <run>/metrics.json

# Record exactly one profiler package per variant/scenario/iteration.
# The app supplies its actual ProcessInfo PID through the existing control
# handshake; XCUIApplication has no supported processIdentifier member.
# The runner configures a fresh xctestrun beside Xcode's original test-run,
# waits for explicit Instruments readiness before XCTest taps the native Begin
# control, checks identity-matched native completion, gracefully stops xctrace
# and preserves its package. The #219 traced protocol has thirty exact identities,
# 2...30 inclusive; it is not 0...30 (31 identities) and does not renumber the
# non-traced 0..<30 loops or transfer prior evidence. Repeat for each iteration
# 2...30 with a new run directory. --window bounds deferred work, not the measured
# iteration window.
# --template defaults to Animation Hitches. Select SwiftUI explicitly for the
# currently supported simulator target; an unsupported template remains an error.
python3 -I bench/ios/iteration_trace_runner.py \
  --target-udid <owned-udid> --derived-data <build-output-directory> \
  --variant <generated-or-reference> --scenario <scroll-or-stateUpdate-or-startup> \
  --iteration <2-through-30> --source-revision <clean-committed-revision> \
  --template 'SwiftUI' --run-directory <new-iteration-run-directory>

# Select a template supported by the exact target. Animation Hitches and the
# SwiftUI template can include an unsupported Hitches instrument on another
# simulator. A nonzero recorder exit is never accepted merely because a package
# exists. The chosen template is retained in the result metadata and acquisition
# command; no profiler output substitutes for the native CADisplayLink metric.

Each iteration writes a uniquely named final xctestrun beside the original in `Build/Products`, preserving
`__TESTROOT__` resolution without modifying that original. The run directory retains an identical
`iteration-trace-config.xctestrun`, the build manifest and `iteration-trace-config.json`. The receipt separately
records the configuration SHA-256, build-manifest SHA-256, source revision, control directory and iteration. The
runner reads back the final hosted-test environment and refuses to replace an existing configuration or receipt.

# Equivalent lower-level recorder command used by the driver after the app
# publishes its PID. Do not use a filename as a substitute for the handshake:
xcrun xctrace record --device <owned-udid> --template 'Time Profiler' \
  --attach <observed-running-app-pid> --window <bounded-deferred-work-window> \
  --output <run>/<variant>-<scenario>-<iteration>.trace

# The driver archives only after xctrace exits successfully, emits exact raw
# identity, bytes and SHA-256, and retains the handshake and recorder logs.
# xctrace writes a package directory; the reporter requires an ordinary raw file.
# Archive only after recording finishes. Repeat for every exact iteration and do
# not infer identity from the filename. This emits byte count and SHA-256 for the
# manifest, rejects links and never replaces an existing archive.
python3 -I bench/ios/archive_trace.py \
  <run>/<variant>-<scenario>-<iteration>.trace \
  --output <run>/raw/<variant>-<scenario>-<iteration>.trace.zip

# Preserve the native result bundle as an ordinary ZIP for independent review.
ditto -c -k --keepParent <run>/results.xcresult <run>/raw/results.xcresult.zip
python3 -I bench/common/report.py <run>/manifest.json --output <new-report-directory>
```

`run.sh` is an intentionally conservative initial driver and currently selects the simulator destination. Its read-only
probe rejects unavailable or not-booted targets. Before any physical measurement, add an explicit `devicectl`
availability/identity probe and the `platform=iOS,id=<udid>` destination; do not infer physical availability from a
`generic/platform=iOS` compile. A generic device compile is not a device result.

The per-iteration driver uses a new control directory for each app launch. The app publishes its actual
`ProcessInfo.processInfo.processIdentifier` with the exact source revision, variant/scenario/iteration. The UI test
checks that native packet, then waits for the app to observe the runner's identity-matched recorder-ready file. Only
then does it tap the native Begin control inside the safe area; an overlay covered by the List can look hittable to
XCTest without delivering the action. The explicit native Begin writes its own identity-bound acknowledgement before
starting the unchanged single scroll destination or eight state updates. The app and UI test both validate the
resulting native completion, including PID, before the runner stops recording. The runner rejects missing, stale,
duplicate or mismatched identity/readiness/completion packets, sends SIGINT only to its own `xctrace` child, waits for
successful package completion, and archives before releasing the UI test. No shell duration substitutes for a native
metric.

For a traced `startup` iteration, recorder readiness still precedes Begin. The app then completes only from the
`CACurrentMediaTime` first-display timestamp that `BenchmarkDisplayRecorder` captured at scene activation. The
native completion packet carries that timestamp as a canonical round-trippable decimal string with its clock name and
the same revision, variant, scenario, iteration and PID. A string avoids both Foundation dictionary/`NSNumber`
comparison ambiguity and independent JSON number formatting; the UI test and runner require exact string equality,
round-trip it to the original `Double`, and reject missing, non-canonical, non-finite, non-positive or mismatched
evidence without a tolerance. The receipt retains the same string in monotonic `native_first_display` evidence, not a
shell stopwatch duration or an inferred startup time. The separate 30-iteration `XCTApplicationLaunchMetric` suite
remains unchanged and supplies distinct platform launch samples.

Run the control-plane and source-wiring tests with:

```sh
python3 -I bench/ios/iteration_trace_runner_test.py -v
python3 -I bench/ios/iteration_trace_source_test.py -v
python3 -I bench/ios/iteration_startup_trace_test.py -v
python3 -I bench/ios/archive_trace_test.py -v
```

These use synthetic processes and packages, not Instruments or timing evidence. The native driver requires an
authorized macOS toolchain, a supported Python version and an explicitly owned, already-running target. Real Xcode
compilation, XCTest and Instruments acquisition must be recorded separately from these tests. The original cold-start
test still uses 30 `XCTApplicationLaunchMetric` iterations. The original non-traced scenario entry points remain
available but the complete 30-iteration traced collection must use the new per-launch driver. Simulator results must
remain explicitly labelled and cannot close the physical-device gate.

Partial generated/reference simulator traces have exercised the earlier capture protocol on an earlier integrated
revision; #219 retains their exact revisions, target/toolchain labels and private-artifact checksums. Those artifacts
do not belong to a later merge or PR head, and they are not a completed paired benchmark or report PASS.

For scroll and state update, the runner's retained `raw/native-samples.json` is the durable final sample artifact.
Its immutable identity and SHA-256 are in `raw/iteration-trace.json`; finalizers must use this packet rather than export
`refract.bench.frames.v1` from `UserDefaults`. The app may still persist that key for diagnostics, but a periodic plist
snapshot with `completedIterations == 0` neither replaces nor invalidates the validated final packet. Startup continues
to use its exact native first-display packet and the unchanged cold-start launch metric. Complete native sample
collection, memory/binary pairing and fail-closed report validation remain required.

## Regression and evidence policy

Use `bench/common/report.py`. It requires 30 pairs of samples for each scenario, one native profiler trace per
iteration, exact source/toolchain/target provenance, finite millisecond samples and SHA-256 verification. It does not
accept a median as p99 or a trace reused across iterations. `CADisplayLink` intervals and Xcode launch metrics are
reported as distinct native definitions; shell elapsed time is never substituted. Keep installed binary bytes and
resident memory bytes separate. The physical-device gate remains open even after a labelled simulator result.
