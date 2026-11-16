# Android generated-vs-native benchmark harness

The app module contains a performance-shaped Compose settings screen and a hand-written reference of the same UI.
**The `Generated*` functions are currently hand-checked contract stand-ins for the source in
`SettingsScreen.swift`, not output produced by the unfinished generator.** Replace them with generator output and
keep this notice until the replacement is in place. There is no benchmark runtime library in either screen.

`report.py` pairs `Generated` and `Reference` results from the benchmark integration, reports raw samples and
p50/p99, rejects missing pairs, non-finite values and different build/device contexts, and returns nonzero for a
latency regression beyond 5% AND 0.1 ms. The absolute gate is time-based; memory and frame-overrun metrics are
reported separately, not compared with a millisecond threshold. Microbenchmark aggregate medians are diagnostic,
not a fictitious p99 sample.

## Current integration status

- The app compiles for release with the pinned Compose BOM, material3 `Switch`, stable lazy-list keys/content type,
  and narrow `State<T>` reads.
- `report_test.py` verifies parsing, pairing, quantiles, environment checks and threshold behavior.
- Both real setting-row microbenchmark variants pass on an AOSP API 35 x86_64 emulator and produce actual AndroidX
  JSON with 50 timing samples and 5 allocation samples per variant. The parser accepts this real format, including
  top-level context and `EMULATOR_` method prefixes. The real-row comparison (generated p50 100.541ms, reference
  149.006ms; generated p99 170.044ms, reference 615.354ms) passed the emulator gate. Earlier duplicate toy-row
  measurements used different content and are not comparable baselines; these results are not physical-device
  evidence or a generator-wide performance guarantee.
- Macrobenchmark/Microbenchmark instrumentation is present. On the available software-only emulator, startup
  frame completion can exceed the platform's fixed activity-launch deadline (`lastFrameNs=null`) or the system can
  become unresponsive. No successful macrobenchmark result is claimed from that environment. The runner fails
  rather than converting an incomplete trace into a passing report.
- The app disables shrinking to preserve both variant function boundaries, uses debug signing for local
  instrumentation and has a `profileable` release manifest. These are harness choices, not production performance
  claims.

## Prerequisites

Use JDK 17+ (JDK 21 is supported by the pinned AGP) and an Android SDK with API 36/build-tools. Set `ANDROID_HOME`
and `GRADLE_USER_HOME` for your machine, not in repository files. Dependency versions are pinned in
`app/build.gradle.kts`.

```sh
# No device needed:
python3 -I bench/android/report_test.py
bench/android/gradlew -p bench/android :app:assembleRelease :benchmark:assembleRelease

# One fully booted emulator, with a responsive system and external storage mounted:
bench/android/run-emulator.sh bench/android/results/emulator-01
```

`run-emulator.sh` checks `ro.kernel.qemu`, boot completion, external-storage writability, disables animations,
runs the release instrumentation, reads only `*benchmarkData.json`, and records the emulator probe in the report.
It exits nonzero for build/test failures, timeouts or missing results. AOSP images without Google services need the
same startup/rendering stability checks; slow first frames are not accepted as passing startup measurements.

The Gradle wrapper bootstrap and distribution have pinned versions. On a new machine the wrapper downloads its
distribution from the public Gradle service; no local proxy or internal mirror is configured in this project.

## Adding real generated benchmarks

Regenerate `GeneratedSettingsScreen.kt` from `SettingsScreen.swift`, retain the generated header, and diff the
native semantics against the reference. Do not benchmark a hand-edited "generated" file. Add fixtures for every new
performance rule in `Fixtures/performance/`, then measure any changed native pattern before merging. A compile
success alone cannot satisfy goal 2, and emulator-only measurements cannot close the physical-device evidence gap.
