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
- Macrobenchmark/Microbenchmark execution and an emulator-labelled report are **not yet complete**. Their
  instrumentation integration is a separate follow-up for issue #9. Compiling this app is not a passing performance
  measurement, and no physical-device result exists.
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
bench/android/gradlew -p bench/android :app:assembleRelease
```

The Gradle wrapper bootstrap and distribution have pinned versions. On a new machine the wrapper downloads its
distribution from the public Gradle service; no local proxy or internal mirror is configured in this project.

## Adding real generated benchmarks

Regenerate `GeneratedSettingsScreen.kt` from `SettingsScreen.swift`, retain the generated header, and diff the
native semantics against the reference. Do not benchmark a hand-edited "generated" file. Add fixtures for every new
performance rule in `Fixtures/performance/`, then measure any changed native pattern before merging. A compile
success alone cannot satisfy goal 2, and emulator-only measurements cannot close the physical-device evidence gap.
