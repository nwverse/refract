# Repository checks and CI

This page describes the checks owned by `ci.yml` and how to run them locally. The checks add no application
dependency, generated-code runtime or host-application setup.

## Local checks

Run these commands from a repository checkout:

```sh
python3 scripts/privacy_check.py
python3 -I scripts/test/test_privacy_check.py
python3 -I scripts/test/test_doc_paths.py --self-test
python3 -I scripts/test/test_doc_paths.py
node scripts/test/pr_needs_issue_test.mjs
python3 -I scripts/test/test_harmony_toolchain.py
actionlint
```

The privacy tests copy the scanner into temporary git repositories and replace its home, configuration and git
configuration with fixture values. They exercise tracked, staged, range, commit-message and squash-message scans;
positive and negative samples; redacted path diagnostics; binary files; symlinks; and unrelated histories. They do
not read the developer's private word list. The ordinary privacy command remains a separate required check because
it scans the real checkout with the machine's private values.

The documentation checker verifies that every Markdown file under `docs/` is covered by the Docs index in
`CLAUDE.md`, including files under an indexed directory such as `docs/lessons/`. It resolves relative Markdown links
and images, rejects links that leave the repository, and checks literal repository paths in inline code. Fenced
examples, command arguments and explicit placeholders are not paths. It does not validate external URLs or heading
anchors, which would require network access and a Markdown parser.

The HarmonyOS preflight unit tests use synthetic executable files and mocked process calls; they verify argument and
missing-tool behavior without running or imitating a vendor compiler. Run the environment probe separately with
`python3 scripts/check_harmony_toolchain.py --check-only`. A missing authorized SDK must return the documented
nonzero blocker, never be skipped and reported as a native compile pass. The actual application and native-test build
commands and the acquisition blocker are in `docs/harmony-toolchain.md`. No public CI HarmonyOS compile job is enabled
until a licensed reproducible distribution is available.

Install actionlint separately when changing `.github/workflows/`. CI downloads the pinned release only when a
workflow changes, validates the archive against the SHA-256 published in that release's checksums file, and invokes
the binary from an empty temporary directory.

## CI jobs

The workflow runs on pull requests, pushes to `main`, and manual dispatch. It has read-only repository permissions
and never interpolates pull-request text into a shell command. Swift, Android compile, repository checks and
changed-workflow linting are independent jobs. The required Swift, Android compile and repository jobs run on every
pull request; workflow linting runs on the changed workflow set. Each Swift job also performs two clean CLI package
builds and executes its own relocated native artifact; Linux does not build or verify a macOS artifact and vice
versa. Archives remain in the runner's temporary directory and are never published.

The documentation check runs unconditionally on every pull request and push. It has no missing-path exceptions:
every maintained document must be indexed, every relative Markdown link and image must resolve inside the repository,
and every literal repository path in inline code must exist. If a promised path is renamed, update its original
documentation references in the owning change rather than deleting a broken reference.

Both Swift jobs run `swift build`, the complete `swift test`, and `python3 -I scripts/test_swiftpm_consumer.py`. On macOS the test step first derives and validates XCTest and `libXCTestSwiftSupport` locations from `xcrun --show-sdk-platform-path`, exporting the corresponding framework/library search paths. This keeps the SwiftPM testing helper's dynamic loading independent of a machine-specific Xcode installation path; it changes neither the tests nor the app's runtime. The consumer test uses the real plugin with explicit inputs and plugin-work outputs; it checks no-op scheduling, dependency invalidation, fail-closed output checks and sandbox boundaries. macOS compiles an ordinary SwiftUI host library, not an Xcode iOS app or a device. Linux uses an isolated syntax-only module for build-order testing and makes no SwiftUI claim. Kotlin and ArkTS are staged/committed generation outputs, not languages compiled by SwiftPM. The jobs then run the documented `swift test --filter GoldenTests` regenerate-and-diff check. They then require no fixture diff and no unexpected generated or dependency files. CLI
integration tests accept `REFRACT_CLI_PATH`, which the workflow derives from `swift build --show-bin-path`; this
avoids assuming that SwiftPM test runners and products use the same directory layout on every operating system.
The jobs request Swift 6.4.2 on Ubuntu 24.04 and macOS 26. The stable setup-swift release has a hard-coded catalog that
ends at 6.2.1, so the workflow uses the pinned v3.0.0-beta.1 commit that installs through Swiftly. Its Linux path
verifies the Swiftly archive with Swift's official GPG keys; signature verification is not disabled. The pinned
installer does not modify the developer's shell profile. This pin needs a follow-up when a stable setup-swift release
supports the requested version. The manifest's Swift 6 language mode is preserved, but `Package.swift` currently also
enables an upcoming compiler feature that is redundant in Swift 6; Swift 6.0.3 rejects it. #1 owns the package
compatibility fix, recorded in that issue, and #11 does not bypass it by lowering language mode or changing shared
compiler flags. Dependencies stay locked by `Package.resolved`. There is no skip for the Swift or fixture jobs.
macOS CI verifies generator portability; it does not constitute an iOS device or simulator measurement.

## Android generated-code compile and JVM behavior gate

The `android-compile` job proves that the committed generated Kotlin compiles with the documented Android
toolchain on every pull request and on every push to `main`. It also runs the opt-in Gradle generation and
committed-output check against the actual CLI, plus native animation lifecycle tests on the JVM. A generator change
can pass the golden tests while producing Kotlin that no longer builds; this job catches that at CI time.

The job runs on Ubuntu 24.04 and uses no emulator or device. Its steps:

1. Build the `refract` CLI with the same locked dependencies as the Swift job.
2. Run `refract check` over every shared example input and both committed native output directories. This generates
   only in memory and rejects missing, stale or unexpected Kotlin/ArkTS files without writing to the checkout.
   Run `python3 scripts/check_examples.py` to independently regenerate the example sources through the actual CLI,
   validate resource catalogs and confirm the shared iOS source set. The final unexpected-file check rejects any
   unexpected drift.
3. Install JDK 21 (Temurin) and a pinned Android SDK: platform `android-37.2`, build tools `37.0.0`, and the
   command-line tools zip whose SHA-256 is recorded in the workflow. The pinned toolchain mirrors the documented
   values in `examples/android/README.md` and `examples/android/app/build.gradle.kts`.
4. Export the built CLI as `REFRACT_CLI_PATH` and its exact `refract --version` line as
   `REFRACT_REQUIRED_VERSION`, then run `./gradlew --no-daemon :app:checkDebugRefract
   :app:compileDebugKotlin` from `examples/android/`. The complete version identity is checked before generation or
   publication; local development builds identify their source revision as `unknown-source-revision`, while packages
   carry an exact source revision. The Gradle plugin in `tools/gradle/` registers per-variant
   generation through Android's generated-source API. It compiles the fresh output under `app/build/generated/`,
   while `checkDebugRefract` invokes the CLI's read-only committed-output check. The checked-in Gradle wrapper
   (`gradle-wrapper.properties`) pins Gradle 9.8.2 with its distribution SHA-256; the wrapper downloads Gradle
   through `services.gradle.org`. Android Gradle Plugin, Kotlin and the Compose BOM are pinned in the same
   Gradle scripts; no version is left to resolve at CI time.
5. Restore `~/.gradle/caches` and `~/.gradle/wrapper` via `actions/cache` keyed by the wrapper and Gradle build
   scripts. The cache is read-only on pull requests from forks. The job never runs `gradlew --write-locks` or
   accepts an untrusted lockfile change as part of the gate.
6. Run `python3 scripts/check_fixture_compilation.py` to regenerate every fixture listed in
   `examples/android/fixture-compile-manifest.txt` through the CLI, diff the output against the committed
   `Expected.kt`, and stage the Kotlin plus the fixture's `values/strings.xml` under
   `examples/android/fixtures/src/main/`. The staged files are `.gitignored`; they are produced on every CI run
   and never committed.
7. Run `./gradlew --no-daemon :fixtures:compileDebugKotlin` from `examples/android/`. The `:fixtures` module
   (`examples/android/fixtures/`) is an Android library whose `namespace = "refract.generated"` matches the
   package declared by every fixture's `Expected.kt`, so the generated code's `R` class is `refract.generated.R`
   exactly as the fixtures reference. Adding a fixture to the compile set is a manifest-only change; there is no
   skip list, so a new compile failure must be fixed in the same PR.
8. Run `./gradlew --no-daemon :fixtures:testDebugUnitTest`. Robolectric 4.18 and the Compose test rule execute the
   unmodified generated save-confirmation caller with a test-provided `MotionDurationScale`. The tests cover the
   generated call's final stable state, identity replacement, exit removal, zero scale and leaving composition.
   The app-owned implementation is added to the fixture module through the AGP `kotlin` source-set directory;
   `java` source-set additions do not feed AGP 9's built-in Kotlin compilation. The injected scale is not a
   physical-device reduced-motion settings test. Gradle resolves the pinned Android-all artifact before the test,
   which runs with Robolectric's offline dependency directory so a second runtime downloader is not required.
9. Run `./gradlew --no-daemon :app:testDebugUnitTest` from `examples/android/`. The `src/test` source set invokes
   the same CLI-generated `SettingsScreen.kt` that the compile gate checks, in the real application resource package.
   This is essential: an Android library's local test APK does not include a dependent application's resource table,
   so numeric `R` IDs can otherwise resolve to unrelated dependency strings. Tests first verify the actual localized
   strings. Robolectric 4.18 and Compose UI tests run against Android API 35 with native graphics in a fixed 400×800dp
   window. Tests inspect visible section and row labels, the notification label's bounds relative to its switch,
   `Role.Switch`, toggle and click actions, state updates, text input and the save callback. A recording
   implementation of the generated `SettingsModel` supplies native state; no hand-written replacement screen is used.
10. Upload `app/build/reports/native-jvm-compose/` and the JUnit HTML reports as the
    `native-jvm-compose-settings` artifact. It contains explicitly labelled Native JVM Compose light/dark PNG captures
    and the observed dark-mode semantics tree. This is rendering and interaction evidence only: **it is not an
    emulator, a device screenshot, a cross-platform visual-parity result or a performance measurement.** The captures
    must be inspected rather than inferred from a green test. Tests and their dependencies are confined to the app's
    test source set and add no runtime dependency to generated code or consumers.
11. Reject any untracked files left in the checkout after compilation and tests.

The `:app:compileDebugKotlin` and `:fixtures:compileDebugKotlin` gates are compile-only. They produce no APK, no
emulator or device run, and no performance measurement; `docs/GOALS.md` goal 2 is not exercised by those jobs and no
such claim may be inferred from them. The separate JVM tests do not close that gap. HarmonyOS remains unverified in
CI until a Linux-compatible hvigor toolchain is obtained; that gap is tracked separately and is not hidden by this
job. To run the same checks locally, follow `examples/android/README.md`: build the CLI, run
`scripts/check_examples.py` and `scripts/check_fixture_compilation.py`, set `REFRACT_CLI_PATH`, then
`./gradlew :app:checkDebugRefract :app:compileDebugKotlin :fixtures:compileDebugKotlin :fixtures:testDebugUnitTest
:app:testDebugUnitTest` with `ANDROID_HOME` and a JDK 21 on `PATH`. Run the `tools/gradle/` functional tests as
documented in the example README to cover incremental generation and missing-tool behavior.

The job is required: a pull request that breaks generated Kotlin compilation, leaves stale committed output, or
changes the Android toolchain must update the generated files or the toolchain pins in the same change rather than
being merged with a red job.

## Branch integration

Other changes must merge the latest `origin/main` before local verification. The main CI workflow does not use
third-party mutable action tags, does not request write access, and does not check out code for the separately
maintained, manual issue-link enforcement workflow.
