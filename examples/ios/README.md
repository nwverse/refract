# iOS shared-source example

`RefractExampleApp.swift` contains hand-written navigation and a native profile. The destination `Hello()` is the
same view as `../../shared/Hello.swift`, compiled directly as SwiftUI. No Refract package, runtime or generated Swift
is part of this target. The Xcode project references that shared file explicitly; do not replace it with a copied
platform-specific screen.

## Build on macOS

Requirements: Xcode 16.3 or later with file-system-synchronized groups, an iOS 18 SDK, and a local simulator or
signing configuration appropriate to the destination. From this directory:

```sh
xcodebuild -project RefractExample.xcodeproj \
  -scheme RefractExample \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

**Not verified on macOS.** Linux has no SwiftUI or Xcode, so this project has not been compiled in the current
environment. The view body is identical to the canonical `Fixtures/hello/Input.swift`, and the shared-file reference
is part of the project rather than an external runtime dependency. A successful generator or Android build is not
evidence for this iOS target. Device screenshots and performance results are also unavailable.
