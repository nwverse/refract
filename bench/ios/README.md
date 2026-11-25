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
The original compile-only change created, started, restarted, used or stopped no simulator and installed no application;
later, separately coordinated per-iteration simulator execution is recorded below and is not a device result.

`build.sh` requires a clean committed checkout before and after compilation. It writes an immutable
`refract-build-provenance.json` in DerivedData with the exact source revision, original xctestrun SHA-256 and the
app/UI-test bundle file identities. For the paired reporter, the schema-2 manifest's
`environment.build_configuration` must contain exactly `name=Release`, `target=iphonesimulator` and `derived_data`.
The latter is a nonempty relative path from the evidence manifest to the original DerivedData directory; absolute
paths, `..`, backslashes and symbolic links in any path or ancestor component are rejected. For example:

```json
{
  "name": "Release",
  "target": "iphonesimulator",
  "derived_data": "products/DerivedData"
}
```

Retain that original `Build/Products` tree beside the evidence. The reporter recomputes the source xctestrun and exact
app/test bundle directory/file records from it, comparing every file byte count, executable flag and SHA-256 with the
JSON rather than merely checking SHA syntax. Well-formed but incorrect values and malformed entries fail with an
evidence error. The canonical producer is accepted only for `SIMULATOR`. The single shared app/test build contains both
variant execution paths; timing and resource artifacts separately retain their selected variant identities. No
generated/reference app split is invented for reporting. The trace runner requires this manifest and rechecks every
listed file before launch. Do not pair a checkout at one revision with products built from another, reuse a
generic-device build or reuse products without their manifest; rebuild in a new DerivedData directory instead.

## Scenario construction

The generated and reference screens have the same explicit `.plain` list style, title/subtitle typography, switch
accessibility labels and stable `Identifiable` rows. `BenchmarkScrollDriver` wraps both hosts in the same
`ScrollViewReader`; a shared native task issues identical programmatic scrolls. Local update performs eight toggles
per iteration through the same model. The traced protocol uses the fixed inclusive identities 2...30: **29 identities**,
not 0...29 or 0...30. Twenty-nine traced acquisitions are retained as identities; one iteration-30 pair is one of those
29 identities, not completion of the matrix. The separate `XCTApplicationLaunchMetric` cold-start suite retains its
30 non-traced iterations below; its count does not change this traced set.

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
before completion or archive acceptance. JSON identities use actual integer encodings rather than Boolean coercion.
Interval samples must be finite, positive and no greater than `2^53` milliseconds, without Boolean coercion or
lossy large-integer conversion; a Swift `NSNumber` cast alone does not enforce that boundary. Exact integer `2^53`
and ordinary fractional Double samples remain valid. Larger values fail closed because Foundation can decode a large
integer spelling as the same rounded `d` value as a legitimate huge Double; the validator cannot recover or infer the
original spelling. The runner persists this packet directly as `raw/native-samples.json` and
binds its path and SHA-256 in `raw/iteration-trace.json`; finalizers consume that durable file, not preferences.

`UserDefaults` is diagnostic only. Its asynchronous plist can still contain a periodic snapshot with
`completedIterations == 0` after native completion; no sleep, polling or `UserDefaults.synchronize()` can turn it into
the completion channel. A stale diagnostic plist never overrides a valid final completion packet. The separate startup
packet retains its exact `firstDisplay` timestamp, and the separate 30-iteration cold-start metric remains unchanged.
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
# and preserves its package. The #219 traced protocol has 29 exact identities,
# 2...30 inclusive; it is not 0...30 (31 identities) and does not renumber the
# separate non-traced 0..<30 XCTApplicationLaunchMetric loops or transfer prior
# evidence. Repeat for each iteration
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
shell stopwatch duration or an inferred startup time. The selected `*StartupTrace` XCTest measures the same unchanged
`runTracedIteration` helper once with `XCTApplicationLaunchMetric` and `iterationCount = 1`. The two separate
30-iteration cold-start tests are unchanged; neither those automatic measurement ordinals nor array indexes supply
traced identities `2...30`.

After that exact XCTest succeeds, the runner exports `test-results tests` and `test-results metrics --test-id
<RefractBenchUITests/testGeneratedStartupTrace()-or-testReferenceStartupTrace()>` from its own `results.xcresult`.
It retains the raw JSON bytes and exact commands in `raw/exports/`. The normalized `raw/metrics.json` selects exactly
one native `com.apple.dt.XCTMetric_ApplicationLaunch-AppLaunch.duration` measurement in explicit seconds, converts it
once to milliseconds, and carries a checksum-based `metric_selector` for `paired_report.py`. The selected test,
passing result, target, trace receipt and configuration receipt are bound to the same run. Before invoking either
xcresult export command, the exporter requires the canonical `control/native-process.json`, retained request,
`control/native-completion.json` and forwarded completion to agree on session, revision, variant, startup iteration
and one strictly positive integer native PID; the iteration receipt must match that PID, not supply an unchecked
identity. Boolean, floating-point, missing, non-positive and unrelated PIDs fail before export. The selected
measurement contains the exact `pid` inside the selector checksum, and provenance retains each native packet's
relative path and SHA-256. Receipt/configuration identity and schema fields require exact JSON types, including integer
schema 1, `device_result is False`, and an exact positive integer PID. Duplicate object keys, nesting beyond 128 levels,
inexact arbitrary-precision integer conversion, and malformed xctestrun XML are controlled evidence errors. Integer
seconds are converted only when both the binary-float seconds and millisecond values preserve the exact rational value;
ordinary exact integer and floating-point durations remain supported. Empty, duplicate, unrelated, non-finite or
non-positive measurements fail without publishing a duration.
Each xcresulttool invocation has a separate 60-second local exporter watchdog. It applies only after native acquisition
and is not a production performance threshold or a replacement for the unchanged XCTest/native completion deadlines.
A nonblocking selector drains both pipes; stdout is limited to 16 MiB while streaming, stderr retains only a bounded
diagnostic tail, and an overrun or deadline kills and reaps the exporter's own process group. No partial oversized JSON
is retained. `raw/exports/` may already contain unrelated `resident-memory.json` or `installed-binary.json` evidence;
the exporter preserves those files but refuses any existing `xctest-tests.json`, `xctest-metrics.json` or
`raw/metrics.json` before running xcresulttool. The export directory must be a real directory, never a symbolic link.
`firstDisplay` remains a separate
scene-activation instant and is never subtracted from another timestamp or relabelled as elapsed launch time.
This UI-test source change requires a new build identity. For separately authorized native verification, rebuild the
exact committed head with `DERIVED_DATA=<fresh-new-head-build> bench/ios/build.sh`, then use the existing traced-runner
command with that new DerivedData and a fresh run directory. Do not reuse old products, transfer an old cold-start
result, or treat the old empty metrics exports as backfilled durations.

Run the control-plane and source-wiring tests with:

```sh
python3 -I bench/ios/launch_metric_test.py -v
python3 -I bench/ios/iteration_trace_runner_test.py -v
python3 -I bench/ios/iteration_trace_source_test.py -v
python3 -I bench/ios/iteration_startup_trace_test.py -v
python3 -I bench/ios/archive_trace_test.py -v
```

These use synthetic processes and packages, not Instruments or timing evidence. The native driver requires an
authorized macOS toolchain, a supported Python version and an explicitly owned, already-running target. Real Xcode
compilation, XCTest and Instruments acquisition must be recorded separately from these tests. The original cold-start
test still uses 30 non-traced `XCTApplicationLaunchMetric` iterations. The original non-traced scenario entry points
remain available but the complete 29-iteration traced collection must use the new per-launch driver. Those 29 traced
acquisitions do not by themselves satisfy issue #219's documented at-least-30-iteration acceptance gate, which remains
unchanged. Simulator results must remain explicitly labelled and cannot close the physical-device gate.

Partial generated/reference simulator traces have exercised the earlier capture protocol on earlier integrated
revisions; #219 retains their exact revisions, target/toolchain labels and private-artifact checksums. Those artifacts
do not belong to a later merge or PR head, and they are not a completed paired benchmark or report PASS. The final
new-revision evidence and the separately counted historical inventory are documented below.

For scroll and state update, the runner's retained `raw/native-samples.json` is the durable final sample artifact.
Its immutable identity and SHA-256 are in `raw/iteration-trace.json`; finalizers must use this packet rather than export
`refract.bench.frames.v1` from `UserDefaults`. The app may still persist that key for diagnostics, but a periodic plist
snapshot with `completedIterations == 0` neither replaces nor invalidates the validated final packet. Startup retains
its exact native first-display packet and, on a successful new-head run, its separate selector-bound `raw/metrics.json`
launch duration. Existing runs whose metrics export is empty cannot be backfilled. The downstream #380/#395 manifest
exporter still consumes the historical `raw/exports/xctest-metrics.json` input; it must explicitly adapt to this
normalized `raw/metrics.json` and its `metric_selector` rather than silently changing inputs in this PR. Its existing
`selected_duration` validation preserves the added PID field and verifies its selector checksum. Complete native sample
collection, memory/binary pairing and fail-closed report validation remain required.

## Offline schema-2 export of retained iterations

`export_iteration_manifest.py` transforms a complete set of accepted existing run directories without invoking
Xcode, Instruments, a simulator or a device. It requires all 174 generated/reference/scenario identities in `2...30`,
with no missing, duplicate or renumbered member. Each run must retain its exact `accepted-evidence.json`,
`retained-file-hashes.json`, the archived/executed trace configuration, `iteration-trace.json`, profiler and xcresult
archives. Configuration identity includes the canonical `source_xctestrun`, configuration SHA-256, deterministic
revision/control/iteration filename and those exact values in the archived hosted-test environment. Frame runs also
require `raw/native-samples.json` with the iteration receipt's session and the original/alias native resources from
`raw/iteration-trace.json`. A frame run exposes `raw/exports/resident-memory.json`; a startup run has no such alias.
Only each variant's `startup/2` exposes `raw/exports/installed-binary.json`. Every original `raw/native-resources.json`,
`raw/native-memory.json` and `raw/native-binary.json` remains retained, and the selected alias must have identical bytes
and SHA-256. Startup normally requires the selector-bound normalized `raw/metrics.json` produced by #400 at
`cf6d15ab833017d2df48d7f47d89341cc54381e6`, including its embedded selector, exact positive native PID, native-packet
and raw-export SHA-256 provenance. Its exact-selector raw exports remain under `raw/exports/`; the producer must share
an already-created exports directory with #402 without replacing an existing file. Older already-accepted inputs may
explicitly use the legacy `raw/exports/xctest-metrics.json` normalized-object contract when `raw/metrics.json` is
absent; that compatibility never substitutes the raw array or firstDisplay for a missing producer metric. Those
resource files follow the reporter's explicit revision/identity/PID/bytes schema. Absent or mismatched memory, binary
or normalized startup evidence is an error before any `manifest.json` is created; the exporter never invents or
approximates resources.

The environment input has exactly `source_revision`, `target_label`, `device_result`, `target`, `toolchain` and
`commands`. The toolchain is exactly the accepted `xcode` version. The target's `udid`, `name`, `modelName`, `os_version`
and `architecture` must match both the checksummed `raw/exports/xctest-summary.json` and the legacy tests export. For
normalized startup, the exact-selector metrics testRun supplies the device record and the tests export supplies the
one passing selector/test-plan configuration; the raw native identifier, unit and exact sample array must match the
normalized measurement. Presentation-only metadata such as `displayName` may remain in the raw export: the producer's
selector checksum still binds the complete normalized measurement, and the exporter never strips or rewrites raw bytes. The
CoreSimulator model identifier must also match the retained `target.json`/`simulators.json` and `targets.json` probes.
Input `commands` become `externally_asserted_commands` with an explicit not-reconstructed/not-evidence-verified label.
The exporter cannot recover acquisition history. `environment.commands` identifies only the verified offline export
operation; `export_command_template` is a rerun template with caller-supplied paths, not recovered executed command
text. Normalized startup uses its embedded `metric_selector`. An optional `--startup-selections` file is supported only
for older normalized measurement arrays or when it exactly repeats that embedded selector; a conflicting external
selector is rejected. It binds `source_revision`, `build_provenance_sha256` and a list of
`{variant, scenario: "startup", iteration, index, value_sha256}`. `firstDisplay` remains only a monotonic
completion timestamp and is never used as the startup scalar. The durable accepted-evidence finalizer must separately
retain and bind the normalized metrics, its native packets and resource exports; this offline reader does not create
that finalizer inventory.

```sh
python3 -I bench/ios/export_iteration_manifest.py \
  --run-root <retained-runs-root> --derived-data <original-DerivedData> \
  --environment <export-environment.json> --startup-selections <startup-selections.json> \
  --output <previously-absent-evidence-directory>
python3 -I bench/ios/export_iteration_manifest_test.py
```

The output gets a deterministic, sorted manifest and checksum-preserved ordinary-file copies under `raw/`, plus the
original canonical app/test products under `products/DerivedData` for reporter recomputation. Nested test-bundle files
are staged once and retain executable bits. The exporter validates the complete staged manifest through
`make_report()` before exclusively creating `manifest.json`; it does not emit a performance report or turn a native
regression into a passing result. An existing output, a symbolic-link input or original DerivedData/product ancestor,
or a source changing during copying is rejected. The tool transforms only evidence belonging to the retained
revision/build/target: it cannot backfill a
new main head or close the physical-device gate. Raw native resource and launch scalar collection is not provided by
this offline tool.
## Published partial execution evidence

The final [joint #219 audit](https://github.com/nwverse/refract/issues/219#issuecomment-7148267250) accepts exactly one
generated/reference pair for each of startup, scroll and stateUpdate at literal iteration 30 and exact revision
`eb16e22b3232625d52b25f5e08f61eaf603f2bd0`. The target is an existing coordinated iPhone 17 Pro iOS 27.0 **SIMULATOR**
(arm64, OS build 24A434), using Xcode 27.2 (27B52), Release simulator build provenance, explicit Time Profiler and the
unchanged 180-second native-completion deadline. The accepted build's manifest SHA-256 is
`2ea39e4479a5743076ea42dc9bdd153115dd06a2d6809cccfa7b4b1e41067de1` and its original xctestrun SHA-256 is
`b17d7896b0e6d950cc8fed64ab0c69101e061a9ec39859d4dea73fabc0181048`. The [separate scroll
reread](https://github.com/nwverse/refract/issues/219#issuecomment-7148285055) and joint audit verify the retained files,
archives and reports; the raw packages remain retained in their private issue evidence locations, not committed here.

| Scenario / identity | Generated / reference native metric evidence | Raw archives and acceptance | Not established |
| --- | --- | --- | --- |
| `startup/30` | Exact `CACurrentMediaTime` firstDisplay `765151.7899704585` / `765183.1509280835`, scene-activation instants rather than launch durations | Independent trace/xcresult archive verification; XCTest 1 passed / 0 failed / 0 skipped per variant; recorder exit 0 | `XCTApplicationLaunchMetric` duration, remaining 28 pairs, complete report, resource pairing or performance/device acceptance |
| `scroll/30` | 75 / 73 finite positive `CADisplayLink targetTimestamp - timestamp` intervals, all tagged 30; not CPU frame durations | Independent trace/xcresult archive verification; XCTest 1 passed / 0 failed / 0 skipped per variant; recorder exit 0 | Per-iteration native p99 scalar comparison, remaining 28 pairs, memory pairing or performance/device acceptance |
| `stateUpdate/30` | 153 / 152 finite positive display-target intervals, all tagged 30; not CPU frame durations | Independent trace/xcresult archive verification; XCTest 1 passed / 0 failed / 0 skipped per variant; recorder exit 0 | Per-iteration native p99 scalar comparison, remaining 28 pairs, memory pairing or performance/device acceptance |

Coverage at `eb16e22` is therefore **1/29 accepted pairs per scenario** under the inclusive 2...30 protocol. These are three
pairs total, not 30 pairs or a performance PASS. The [actual retained-evidence
inventory](https://github.com/nwverse/refract/issues/219#issuecomment-7155061440) separately records 76 accepted pairs
at `95a0f37b88ae0eaf5e815554755f3d4771bcfd5a`: startup 21 (2..22), scroll 27 (2..28) and stateUpdate 28 (2..29). Those
pairs, the rejected old-head iteration-30 attempt and every other historical root are not counted here. No simulator or
toolchain result is promoted to physical-device evidence, and this build/provenance record does not close the general
pinned-toolchain or reproducibility gate.

## Regression and evidence policy

Use `bench/common/report.py` schema 2. It requires the exact iteration identities 2...30, one native profiler trace per
iteration, source/build/target provenance matching every artifact, finite millisecond scalars and SHA-256 verification.
The startup scalar comes from `XCTApplicationLaunchMetric`, never the `CACurrentMediaTime` `firstDisplay` timestamp or
shell elapsed time. Scroll/state-update retain their `CADisplayLink` interval arrays and explicitly reduce each to a
nearest-rank per-iteration p99 before the outer p50/p99 comparison. The reporter verifies that reduction; it does not
accept an unlabelled array, a median as p99 or a trace reused across iterations. Resident memory requires a same-
iteration generated/reference pair with memory-role provenance; installed binary bytes require one pair at the same
build identity with binary-role provenance. Neither resource can be backfilled from another revision. The physical-
device gate remains open even after a labelled simulator result.
