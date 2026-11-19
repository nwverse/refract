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

# Record exactly one profiler artifact per variant/scenario/iteration.
# The --attach PID and time window must be captured from that exact iteration.
xcrun xctrace record --device <owned-udid> --template 'Animation Hitches' \
  --attach <iteration-pid> --time-limit <iteration-window> \
  --output <new-run>/raw/<variant>-<scenario>-<iteration>.trace

# Preserve the native result bundle as an ordinary ZIP for independent review.
ditto -c -k --keepParent <run>/results.xcresult <run>/raw/results.xcresult.zip
python3 -I bench/common/report.py <run>/manifest.json --output <new-report-directory>
```

`run.sh` is an intentionally conservative initial driver and currently selects the simulator destination. Its read-only
probe rejects unavailable or not-booted targets. Before any physical measurement, add an explicit `devicectl`
availability/identity probe and the `platform=iOS,id=<udid>` destination; do not infer physical availability from a
`generic/platform=iOS` compile. A generic device compile is not a device result.

The app helper currently persists raw display samples in its own defaults store. Retrieval must use `devicectl` or the
explicit simulator's data container and preserve the raw JSON before report generation. XCUITest metrics and native
profiler recordings must be correlated by the test's actual iteration identifiers, not by filename guessing. A
repeated per-iteration capture workflow is still required before claiming that the complete harness is executable.
Until those collection and correlation steps are run and inspected, this remains a **compiled reference scenario and
measurement contract**, not a completed measurement harness or a paired result.

## Regression and evidence policy

Use `bench/common/report.py`. It requires 30 pairs of samples for each scenario, one native profiler trace per
iteration, exact source/toolchain/target provenance, finite millisecond samples and SHA-256 verification. It does not
accept a median as p99 or a trace reused across iterations. `CADisplayLink` intervals and Xcode launch metrics are
reported as distinct native definitions; shell elapsed time is never substituted. Keep installed binary bytes and
resident memory bytes separate. The physical-device gate remains open even after a labelled simulator result.
