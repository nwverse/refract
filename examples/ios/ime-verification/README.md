# iOS stock Chinese IME verification host

This directory is a test-only application and XCTest UI-test target for issue #283. It is not a production
application target, a generated-code change or a replacement for the existing iOS example.

`project.yml` compiles the unchanged canonical `../shared/InteropTextInputHost.swift`. The test model and view own
committed drafts, callback observations, focus transfer and removal/reappearance of the original `ComposerScreen`.
`MinimalSourcePrelude.swift` supplies only the existing marker protocols required by that source; it deliberately does
not import the full example's unrelated theme helpers. No production defaults or application navigation are changed.

## Controlled simulator run

Use the existing, explicitly allocated Refract #150 simulator and boot it with the reviewed `sim-boot.sh --profile
stock <UDID>` helper. Do not create, erase or restart another simulator. On macOS with XcodeGen installed, generate
only this project, then run the two UI-test cases serially against the explicit UDID with a dedicated DerivedData
and result bundle. Use unsigned simulator builds and a machine-wide serial build slot when shared with other work.

```sh
xcodegen generate --spec project.yml
xcodebuild -project RefractIMEVerification.xcodeproj \
  -scheme RefractIMEVerification \
  -destination 'platform=iOS Simulator,id=<allocated-udid>' \
  -derivedDataPath <private-derived-data> \
  -resultBundlePath <private-result-bundle> \
  -parallel-testing-enabled NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The configuration test opens the actual Settings keyboard list and confirms/adds stock Simplified Chinese Pinyin.
The editing test uses the native input-mode menu and onscreen letter keys, not `typeText`, paste, direct
`setMarkedText`, synthetic candidates or direct binding mutation. It taps the actual Chinese candidate `你`, transfers
focus to a separate native field, increments the original `focusRequest`, taps the actual Done key, and removes and
restores the host while checking the parent-owned committed draft. The test model records that `onDraftCommit` runs
before `onCommit`.

The observer only reads the actual UIKit text field's `markedTextRange` and return-key callbacks. Capture its
`REFRACT_IME_PROBE` records with `simctl spawn <UDID> log stream` during the test. The checked source does not assume
that a host unified-log query is available after termination; log streaming during execution preserves those records.

Evidence is limited to the named iOS simulator, its exact runtime and the stock system Pinyin mode. It is not a
physical-device, third-party-IME, VoiceOver, performance or Android/HarmonyOS result. Retaining the parent-owned
draft across view removal/reappearance is not process-restoration persistence. `markedTextRange` may briefly contain
the non-ASCII chosen candidate before it clears; the committed editor/binding value and the no-marked-text record
must both be checked rather than assuming candidate selection is atomic.
