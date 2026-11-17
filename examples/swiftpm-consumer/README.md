# SwiftPM consumer build integration

This small package compiles the same `Hello.swift` as its native host target and runs
Refract at build time for Android and HarmonyOS. The application target depends on
neither Refract libraries nor a runtime: only its build-tool plugin is enabled.
Generated Kotlin and ArkTS live outside `Sources/` and are not iOS target resources.

For a local checkout, arrange this directory and the Refract checkout as siblings:

```text
workspace/
  refract/                  # this repository
  swiftpm-consumer/         # this directory
```

The example manifest uses `.package(path: "../refract")`. A released consumer uses
its versioned Refract package dependency instead. The integration test creates this
layout in a temporary directory so it does not write to the source checkout.

## Build on macOS

Build the versioned CLI once, then select it explicitly for both generation commands
and normal builds. Alternatively put its executable on `PATH`; no executable is
downloaded during an application build.

```sh
swift build --package-path ../refract
export REFRACT_EXECUTABLE="$(swift build --package-path ../refract --show-bin-path)/refract"
swift build
```

SwiftPM generates native files under its plugin work directory and compares the
committed `Generated/Android/Hello.kt` and `Generated/HarmonyOS/Hello.ets`. It then
compiles `Hello.swift` and a generated comment-only Swift anchor. The anchor orders
host compilation after generation and has no declarations, initialization, runtime
library, or generated Swift implementation of the view.

To intentionally update committed native outputs, review their changes afterward:

```sh
swift package refract-generate --target RefractConsumer \
  --allow-writing-to-package-directory
swift package refract-generate --target RefractConsumer --check
```

The first command requests package-directory write permission explicitly. The
read-only check and ordinary builds never update committed output.

**iOS/Xcode boundary:** a SwiftPM library is not an Xcode `.xcodeproj` application.
The host source above is ordinary SwiftUI, but running this package on macOS does not
build or inspect an iOS application. The real app and its simulator evidence are in
`examples/ios/`; no new app project is implied here.

## Linux verification

Linux has no SwiftUI. `python3 -I scripts/test_swiftpm_consumer.py`, run from the
repository root after `swift build`, adds a separate **test-only** target named
`SwiftUI` containing only enough declarations to compile the shared syntax. It is
never part of the consumer fixture or a Refract runtime. The test proves real
SwiftPM plugin scheduling, not SwiftUI semantics or iOS compilation.

The generated Kotlin and ArkTS are compared with their committed files, not compiled
by SwiftPM. Android and HarmonyOS use their own native toolchains as documented in
`examples/android/README.md` and `examples/harmony/README.md`.

See `docs/swiftpm-integration.md` for the complete input/output and sandbox contract.
