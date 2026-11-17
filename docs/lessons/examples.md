# Building the mixed-code examples

## Keep hand-written expectations distinct from generated evidence

A native app can compile an expected Kotlin or ArkTS file before the generator exists, but that only verifies the
native boundary. It does not verify that the source parses, that generation is deterministic, or that the generated
output is faithful. Label such files and every resulting build explicitly. Replace them with the canonical fixture's
outputs and add a regeneration diff when the backends land; do not grow a second set of semantic expectations inside
`examples/`.

## Download only completed archives

Do not unpack a Gradle distribution while another background download is still writing it. A `.zip` suffix and an
existing path do not mean the download has completed. Wait for its completion notification, verify the published
SHA-256, and only then inspect and unpack the archive. This prevents both corrupted builds and wasted duplicate
bandwidth on a shared machine.

## Android SDK setup

Keep the Android SDK outside the repository and serialize installation with the shared lock from the local agent
brief. Check whether command-line tools already exist before creating download directories: another workstream may
finish the installation while your script is being prepared. The examples accept `ANDROID_HOME` rather than
committing `local.properties` or a machine-specific path.

## AGP 9 and current Compose compatibility

AGP 9 includes Kotlin Android support. Applying `org.jetbrains.kotlin.android` now fails at configuration time;
retain only the Compose compiler plugin and configure JVM bytecode through `KotlinAndroidProjectExtension.compilerOptions`.
The Android Gradle Plugin and Compose BOM also impose their own compileSdk minimums, independently of the app's
`targetSdk`. For the current example, Compose BOM 2026.09.00 requires SDK 37 while `compileSdkMinor = 2` selects the
installed 37.2 platform. Keep those versions documented together and do not downgrade a fixture's language feature
just to use an older cached compiler.

Scope-sensitive Kotlin modifiers are another app-compile issue: importing `androidx.compose.foundation.layout.weight`
can expose an internal member rather than the intended `RowScope.weight`. The correct call resolves in the `Row`
content receiver. Only real Android compilation catches this; inspecting an expected Kotlin file does not.

## Test what the example actually compiles

## Native JVM Compose uses the application's real resource package

An Android library's local unit-test APK does not include a dependent application's resource table. Generated Kotlin
that refers to the application's numeric `R` IDs can then silently render unrelated dependency strings even though
the real generated layout and native controls are present. Run Robolectric in the application's own `src/test` source
set, assert the actual localized strings before rendering, and inspect the resulting PNGs rather than accepting
nonblank pixels as UI evidence. A test-only Activity supplies a native host; it must never replace the generated
composable. Keep the standard AGP `test_config.properties` and binary-resource path, and use a direct
`Robolectric.buildActivity` controller for the empty host when a test-only manifest overlay is not registered. Resolve
the exact Android runtime through Gradle rather than a second implicit repository downloader.

## Real SwiftUI compilation and simulator ownership

A SwiftUI source file must import SwiftUI unless another language-supported import supplies it; parsing successfully
with SwiftSyntax does not make the source a valid standalone SwiftUI input. Build the actual shared file references
in the Xcode target before claiming iOS compatibility. The #150 baseline caught a missing import in `Hello.swift`;
the fix changed neither its body nor generated Kotlin/ArkTS.

On a shared Mac, create a uniquely named simulator for each verification and pass its explicit UDID to every build,
install, appearance and screenshot command. Do not use `booted`, reboot an existing device or infer simulator
ownership from a name alone. Capture with `simctl io <UDID> screenshot`; desktop `screencapture` is neither needed
nor a substitute for checking the actual app pixels. Read the resulting light and dark images before reporting UI
success, and keep simulator results separate from physical-device or performance claims. External input automation
must remain outside the app and repository, and its downloaded binaries are not evidence artifacts.


A shared source may be ready for iOS while the generator still rejects it for other platforms. Do not commit native
host imports of the missing generated interface merely to show future wiring: that breaks the otherwise working app.
Keep the current generated path compiling and land the host change together with actual generated output. Run
`python3 scripts/check_examples.py` after `swift build` to regenerate and compare committed output, validate mapped
base resources and check the iOS shared-source references. It is a consistency check, not a native compiler.

## A documented command and a native target are not compiler evidence

A separate application can document `devecocli build` without making its SDK available on this machine. Inspect that
workflow read-only, do not copy credentials or change its environment, and distinguish its source pattern from an
actual compiler run. A prepared `ohosTest` target likewise remains unverified until the authorized vendor compiler
accepts the application and test target. Use `docs/harmony-toolchain.md` for the explicit acquisition blocker and
`python3 scripts/check_harmony_toolchain.py --check-only` for a non-installing local preflight. Never make missing
prerequisites pass by supplying a TypeScript parser, a fake SDK, a named stub or an unrelated HAP.
