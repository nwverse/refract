# iOS shared-source example

`RefractExampleApp.swift` contains hand-written navigation, native settings and rollback screens. Shared
`Hello.swift`, `SettingsScreen.swift` and `NativeComponentScreen.swift` compile directly as SwiftUI. The app-local
`RefractModel` / `RefractNativeView` declarations and `AppSettingsModel` implement the same typed model boundary;
`en.lproj/Localizable.strings` supplies the shared localized keys. No Refract package, runtime or generated Swift
is part of this target. The Xcode project references those shared files explicitly; do not replace them with copied
platform-specific screens.

The target also compiles six source-only typed-contract inputs: `InteropNativeMeasurement.swift`,
`InteropPlatformValue.swift`, `InteropPlatformView.swift`, `StateCounter.swift`, `ParentBinding.swift` and
`ModelInterface.swift` in `examples/shared/`. Their unique on-disk basenames avoid Xcode's duplicate
`Input.stringsdata` output; `scripts/check_examples.py` requires each to stay byte-identical to its named canonical
fixture. They exercise `Binding(get:set:)`, typed platform selection, native measurement, directional padding and
ordinary SwiftUI action/label buttons through the real SwiftUI type checker. `RefractSourcePrelude.swift` supplies
source-level, iOS-only declarations: the native-modifier shim returns its receiver unchanged and directional padding
forwards to standard SwiftUI `EdgeInsets`. `MeasurementDesignTokens.swift` owns the measurement fixture's iOS
typography token. None of these declarations performs runtime platform dispatch or links a Refract library.

## Build on macOS

Requirements: Xcode 16.3 or later with file-system-synchronized groups, an iOS 18 SDK, and a local simulator or
signing configuration appropriate to the destination. From this directory:

```sh
xcodebuild -project RefractExample.xcodeproj \
  -scheme RefractExample \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

**Verified on macOS:** Xcode 27.2 built the shared settings target against the iOS 27.2 simulator SDK for an iPhone
17 Pro running iOS 27.0. The baseline failed because `Hello.swift` lacked `import SwiftUI`; adding that import fixed
the compiler error without changing any view body, model, native helper or generated backend output. A successful
generator or Android build is not evidence for this iOS target. The six typed-contract inputs were also compiled by
#150 on the #181 revision integrated with its contemporary main; this is not blanket validation of later changes.

The owned simulator was newly created for this verification and used by its explicit UDID; no existing simulator was
rebooted or modified. The app was installed and launched, and native navigation opened `SettingsScreen`. Both
appearance modes were captured using `simctl io screenshot` and visually inspected. [Light](evidence/settings-light.png)
and [dark](evidence/settings-dark.png) preserve the actual settings-screen pixels, and
[home-light](evidence/home-light.png) shows native navigation into the shared source. The screenshots contain only
this example's placeholder content and simulator status UI. Release an owned simulator with
`xcrun simctl shutdown <UDID>` when finished; do not use `booted` or another owner's device.

For an independent check, create a uniquely owned simulator, pass its UDID explicitly to the destination,
`simctl install`, `simctl launch` and `simctl ui <UDID> appearance light|dark`, and navigate through the actual app
or an external simulator-only automation client. Do not add an automation dependency to the app or commit downloaded
tools.

**Limits:** this is simulator-only rendering evidence, not a physical-device result. No performance was measured.
It does not establish visual equivalence with Android or HarmonyOS, validate every supported SwiftUI construct, or
compile ArkTS. The added named-spacing declarations and compiler inputs still require their own real Xcode pass.
See [the evidence record](evidence/README.md) for the baseline's exact environment, hashes and review notes.
