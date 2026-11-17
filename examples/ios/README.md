# iOS shared-source example

`RefractExampleApp.swift` contains hand-written navigation, native settings and rollback screens. Shared
`Hello.swift`, `SettingsScreen.swift` and `NativeComponentScreen.swift` compile directly as SwiftUI. The app-local
`RefractModel` / `RefractNativeView` declarations and `AppSettingsModel` implement the same typed model boundary;
`en.lproj/Localizable.strings` supplies the shared localized keys. No Refract package, runtime or generated Swift
is part of this target. The Xcode project references those shared files explicitly; do not replace them with copied
platform-specific screens.

The target also compiles the canonical `interop-native-measurement`, `interop-platform-value` and
`interop-platform-view` fixture inputs themselves (displayed with descriptive source names). They exercise
`Binding(get:set:)`, both typed platform-selection helpers, native measurement operations and directional padding
through the real SwiftUI type checker. `RefractSourcePrelude.swift` supplies source-level, iOS-only declarations:
the native-modifier shim returns its receiver unchanged and directional padding forwards to standard SwiftUI
`EdgeInsets`. `MeasurementDesignTokens.swift` owns the measurement fixture's iOS typography token. None of these
declarations performs runtime platform dispatch or links a Refract library.

## Build on macOS

Requirements: Xcode 16.3 or later with file-system-synchronized groups, an iOS 18 SDK, and a local simulator or
signing configuration appropriate to the destination. From this directory:

```sh
xcodebuild -project RefractExample.xcodeproj \
  -scheme RefractExample \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

**Not verified on macOS in this change.** Linux has no SwiftUI or Xcode, so this project has not been compiled in the
Linux environment. Real compiler diagnostics and simulator evidence are tracked separately in #150. The view body of
`Hello.swift` is identical to the canonical `Fixtures/hello/Input.swift`; interop source references are the canonical
fixtures themselves, not copies. Shared-file references are part of the project rather than external runtime
dependencies. A successful generator or Android build is not evidence for this iOS target. Device screenshots and
performance results are also unavailable.
