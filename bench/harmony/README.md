# HarmonyOS benchmark plan and current blocker

## Status

No runnable HarmonyOS benchmark is claimed. The official DevEco Studio/developer pages reachable from this Linux
environment are web application shells, not downloadable command-line compiler artifacts. No unauthenticated,
license-compatible distribution containing an ArkTS compiler, HarmonyOS SDK and `hvigorw` for Linux has been
established. No account was created, credential used, or license accepted by this workstream.

The official starting points are the
[DevEco Studio portal](https://developer.harmonyos.com/en/develop/deveco-studio),
[HarmonyOS command-line documentation](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-commandline),
and [public OpenHarmony performance documentation](https://gitee.com/openharmony/docs/blob/master/en/application-dev/performance/readme-EN.md).
The OpenHarmony performance rules are public and usable for source review, but they do not by themselves supply a
HarmonyOS application compiler, signing toolchain, emulator or device image.

To proceed, a maintainer must obtain the vendor-supported command-line tools and SDK through an authorized download,
including any required interactive account sign-in and terms acceptance, then install them outside the repository.
Record the exact version, license and installation prerequisites in `CLAUDE.local.md` or CI secret configuration;
never commit credentials, private download links or machine paths. An available device or emulator must also be
provisioned with an app-signing/debug certificate through the normal vendor workflow. The needed evidence is:

```sh
command -v node
command -v hvigorw
command -v hdc
command -v hypium
# The installer/version-specific SDK and profile paths are supplied by the maintainer.
# Do not paste credentials, certificate contents or local paths into the issue.
```

Until those commands and the corresponding SDK are present, `swift test` only verifies generator text, not ArkTS
compilation, state observation or frame timing. This blocks execution of the following plan, not the source-level
performance rules in `docs/performance.md`.

## Paired application to implement when the toolchain is available

Mirror `bench/android/SettingsScreen.swift` with two ordinary ArkUI screens: actual generator output and an
independently hand-written `@ComponentV2` reference. Both use the same `@ObservedV2` model with `@Trace` fields,
200 setting rows, stable string keys, `List`/`LazyForEach` and Material-equivalent controls. The generated variant
must be regenerated from the shared Swift source, not copied and edited by hand. On API 18+, use `@ReusableV2` for
homogeneous rows; on API 12–17, leave reuse out rather than substituting V1 decorators.

The native app owns the two entry pages and model implementation. No runtime adapter, observer registry or
benchmark-only native helper is part of either measured screen. Use a release-like signed build with the same
compiler, SDK, optimization and profiling configuration for both variants. The target device model, OS build,
toolchain version, application profile and source revision are recorded with every result.

## Measurements

1. **Cold start.** Force-stop and reinstall/clear only as required by the harness, then cold-launch each entry page
   at least ten times. Capture launch-to-first-frame and launch-to-content-ready times with the SDK's launch/startup
   trace and explicit content-ready marker. Do not substitute shell command elapsed time for application start-up.
2. **List scroll.** Execute the same scripted scroll trace (distance, duration, start/end rows and idle boundaries)
   for each variant. Capture frame timestamps and slow/dropped frames from the system trace with the profiler
   documented in [CPU Profiler](https://gitee.com/openharmony/docs/blob/master/en/application-dev/performance/application-performance-analysis.md)
   and [Typical Traces](https://gitee.com/openharmony/docs/blob/master/en/application-dev/performance/common-trace-using-instructions.md).
   Report frame-time p50/p99 and dropped-frame counts.
3. **Local state update.** Toggle the first setting eight times per iteration, with the same UI Automation action and
   wait for native render completion. Record component render counts and frame-time p50/p99. Use the render-scope
   trace/counters rather than counting log lines from a debug-only wrapper.
4. **Reuse.** On API 18+, count row creation, `aboutToReuse` and `aboutToRecycle` during identical scroll traces;
   assert no stale row content. Check heap size after the same warm-up and the final installed artifact size.
   Profiler trace files remain as audit evidence.
5. **Report.** Normalize raw timestamp samples in an issue-owned script, not handwritten summary tables. Use the
   same lower-is-better gate as Android (greater than 5% AND greater than 0.1 ms for p50 or p99), plus separately
   reported memory, render counts and binary size. Context mismatch, absent samples and missing pairs fail closed.

Use the vendor-supported UI test runner (for example Hypium when supplied by the installed SDK) and `hdc` to select
an explicitly named target. If only an emulator is available, title the report `EMULATOR RESULTS — not device
results`. A physical-device gate still requires a named device and its build information. Do not compare Android
emulator timings with HarmonyOS emulator timings or present either as hardware performance.

## Remaining implementation order

1. Obtain and pin a legal compiler/SDK/toolchain and a signed test target.
2. Compile `Fixtures/performance/arkui-*` and a hand-written `@ObservedV2` model; fix API contracts based on real
   diagnostics rather than weakening fixtures silently.
3. Replace the planned two entry pages with generator output and native reference implementations; test both local
   observation and list replacement.
4. Implement the trace/UI-automation runner and normalized JSON report; first run is explicitly labelled emulator
   or device. Keep raw traces and record the exact commands and limitations in this file.
