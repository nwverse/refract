# Real Xcode compile evidence: platform-selected verbatim text (issue #174)

This record belongs to issue #174. It captures the real SwiftUI compiler's semantic type-check of the accepted
per-platform literal-text source form. No simulator was created, booted or used for this verification; the build
targets `generic/platform=iOS` so it exercises only the iOS Swift compiler and SDK, with no device or simulator
involved. No performance or rendering claim is made.

## Environment

- Date: 2026-11-17.
- macOS 27.2 on arm64; Xcode 27.2, build 27B52; iOS 27.2 SDK (`iPhoneOS27.2.sdk`).
- Branch under verification: `fix/174-platform-text-semantics` (PR #194), archive head exported with `git archive`.

## Source under verification

The canonical fixture `Fixtures/interop-platform-value/Input.swift`, which is byte-identical to the iOS-compiled
input `examples/shared/InteropPlatformValue.swift`, includes:

```swift
Text(verbatim: refractValue(ios: "iOS", android: "Android", harmonyOS: "HarmonyOS"))
```

The iOS source prelude is unchanged from `main`: `refractValue<Value>(ios:android:harmonyOS:)` returns its iOS
argument, so the call above selects SwiftUI's `Text(verbatim: String)` initializer on iOS — the same verbatim,
non-localized semantics that the Compose and ArkUI backends already emit. No runtime text-selection adapter is
introduced.

## Reproducible command

From `examples/ios/`:

```sh
xcodebuild -scheme RefractExample \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  -derivedDataPath ./DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

`-destination generic/platform=iOS` performs a clean build with the iOS device SDK only. No simulator is created,
selected, booted, rebooted, erased or shut down by this command.

## Result

```
** BUILD SUCCEEDED **
```

- `error:` count: 0.
- The only `warning:` is unrelated to the change: `appintentsmetadataprocessor: Metadata extraction skipped, no
  AppIntents.framework dependency found`.
- The build log confirms `InteropPlatformValue.swift` was compiled by the real Swift compiler (paths redacted):

```
SwiftCompile normal arm64 Compiling InteropPlatformValue.swift <workspace>/examples/shared/InteropPlatformValue.swift (in target 'RefractExample' from project 'RefractExample')
SwiftCompile normal arm64 <workspace>/examples/shared/InteropPlatformValue.swift (in target 'RefractExample' from project 'RefractExample')
    builtin-SwiftPerFileCompile InteropPlatformValue.swift
SwiftDriverJobDiscovery normal arm64 Compiling InteropPlatformValue.swift (in target 'RefractExample' from project 'RefractExample')
```

This is real SwiftUI semantic type-check evidence that the accepted `Text(verbatim: refractValue(ios:android:
harmonyOS:))` form compiles against the actual `Text(verbatim: String)` initializer with the unchanged
`refractValue<Value>` prelude. It is not a simulator screenshot, an emulation result, a device benchmark or a
rendering-equivalence claim.

## What is not covered

- No simulator screenshot or runtime rendering inspection was captured; the issue is a build-time source-contract
  divergence, not a visual behavior divergence.
- The rejected bare localized form `Text(refractValue(...))` is a frontend diagnostic
  (`R.string.unsupported_expression`), exercised by `Fixtures/interop-platform-text-localized-rejected` and the
  Swift generator's own tests. It is not presented to the iOS compiler because the generator rejects it before
  any SwiftUI build runs.
- HarmonyOS native compilation is not verified here; no HarmonyOS toolchain is available on the verifying host.
  The ArkTS goldens for the accepted fixture are byte-identical to `main` and remain gated by the generator's
  golden corpus.
- Android native compilation is covered separately by `examples/android/gradlew :fixtures:compileDebugKotlin`
  (compile-only, no device, no emulator). The Kotlin goldens for the accepted fixture are byte-identical to
  `main`.

The complete raw build log contains machine-local absolute paths and is intentionally not committed. The summary
above and the redacted compile-invocation lines are preserved here so the result can be independently reviewed
against the reproducible command.
