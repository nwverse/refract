# Real iOS simulator verification

This record belongs to issue #150. The images are actual simulator screenshots, not mockups, previews or
physical-device results. They show only the public example's placeholder content and simulator status UI.

## Environment and source

- Date: 2026-11-17.
- macOS 27.2 on arm64; Xcode 27.2, build 27B52; iOS 27.2 simulator SDK.
- A newly created iPhone 17 Pro simulator running iOS 27.0, named for issue #150. Its explicit UDID was used for
  every device operation. The pre-existing booted simulator was not booted, rebooted, erased or reconfigured.
- Baseline: `397315e`. The baseline build failed because `examples/shared/Hello.swift` used SwiftUI without importing
  it. The successful app build and screenshots add only `import SwiftUI` to that file; the other shared source,
  native model, navigation and iOS helper declarations are unchanged. No generated backend output changed.
- The simulator was installed, launched and navigated from its native home screen to `Generated settings`. An
  external, isolated simulator-input client was used only for that tap and for accessibility inspection. It is not a
  project, application or production dependency; no downloaded tool is included here.

## Commands

Use a newly created, uniquely owned device and substitute its returned UDID. Never use `booted` for shared-machine
verification: it may select another owner's simulator.

```sh
xcrun simctl create '<unique-owner-name>' \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-27-0
xcrun simctl boot <owned-udid>
xcodebuild -project examples/ios/RefractExample.xcodeproj \
  -scheme RefractExample \
  -destination 'platform=iOS Simulator,id=<owned-udid>' \
  -derivedDataPath <workspace>/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
xcrun simctl install <owned-udid> \
  <workspace>/DerivedData/Build/Products/Debug-iphonesimulator/RefractExample.app
xcrun simctl launch <owned-udid> com.example.refract
xcrun simctl ui <owned-udid> appearance light
xcrun simctl io <owned-udid> screenshot --display=1 <workspace>/settings-light.png
xcrun simctl ui <owned-udid> appearance dark
xcrun simctl io <owned-udid> screenshot --display=1 <workspace>/settings-dark.png
xcrun simctl shutdown <owned-udid>
```

Navigate through the real application UI before capturing settings. Wait for the screen to settle; the initial
launch frame can be blank while the simulator finishes starting. The simulator UI and accessibility service are
sufficient for appearance changes and inspection. If input automation is used, keep it outside the target, select
only the owned UDID and do not add its packages or binaries to this repository.

## Inspection results

| File | Actual inspected result |
| --- | --- |
| `home-light.png` | Native navigation title and links are visible, including the link to shared settings. |
| `settings-light.png` | Light grouped-list appearance. Profile and Preferences section labels, Profile settings, Display name placeholder, enabled Notifications switch and Save are visible without clipping. |
| `settings-dark.png` | The same settings screen remains visible with dark system colors and the enabled switch. No missing controls or clipped content was observed. |

These observations are limited to this screen, device type and runtime. They are not an exhaustive accessibility
audit, a cross-platform visual-equivalence result, a physical-device test or a performance measurement. No frame
rate, timing, memory or startup claim is made. HarmonyOS compilation and Android visual equivalence are outside
this evidence.

SHA-256 of the inspected PNG files:

```text
a1888ac02cab29f9227f9bd202f1769817b63facf9ee1ca8f67c10fa81223cc3  home-light.png
ebb1c94510d74d289fb720b8b6efbcbec9d65f6e6ba723caf500f77cbc45ae6d  settings-light.png
931088594a461558c2d36d08cae1c944f2546fa67808c75f6b451e5fe0a982f0  settings-dark.png
```

The complete raw build logs contain machine-local paths and remain outside the public repository. The relevant
source-located failure and successful build summary are preserved in the issue/PR without private paths. The raw
images themselves are committed so their contents can be independently reviewed against the hashes above.
