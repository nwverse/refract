# Typed native document previews

A document preview is an application-owned `RefractNativeView`, not a Refract file picker, decoder or WebView.
`Fixtures/interop-document-preview/` defines the source ABI and its direct Kotlin and ArkTS calls. The generated
screen accepts an exhaustive `DocumentPreviewState`: `loading`, `ready`, `missing`, `unsupported`, `cancelled` and
`closed`. It passes URI, display name, MIME type, byte count and revision as typed scalars. There is no file-content,
URI-object or decoder parameter.

## Ownership and typed actions

The app decides whether it has permission to read a URI, when to open it, which MIME types it supports, how to
bound and decode the bytes, and when the preview's resources are released. It supplies only metadata to the generated
call. The native implementation never invents a permission grant, resolves a remote URI or silently substitutes a
format. The generated code does not import an Android content resolver, a HarmonyOS file API, a network client or a
Refract runtime.

A native declaration may contain `let onClose: () -> Void`. The caller supplies one checked, synchronous,
zero-argument `RefractModel` method:

```swift
NativeDocumentPreview(
    uri: uri,
    displayName: displayName,
    mimeType: mimeType,
    byteCount: byteCount,
    revision: revision,
    onClose: { model.closePreview() }
)
```

Both mappings declare `action`, with the same source label and argument binding as the other parameters. Compose
emits `{ model.closePreview() }` with target type `() -> Unit`; ArkTS emits `() => { this.model.closePreview(); }`
with target type `() => void`. The callback stays a direct native lambda, not a registry, message or runtime bridge.
Arbitrary closures, function values, arguments and effects are not translated: unsupported forms are `RFNATIVE001` or
`RFNATIVE002` build-time diagnostics. The native action is a native-component parameter only, not a scalar model,
state, binding or general screen-input type.

Cancellation while loading invokes the app-owned `cancelPreview()` model action. Close invokes `closePreview()`
through the typed native action. The app clears pending work and decoded content, chooses the resulting state, and
releases its own resources. A revision and native key identify replacement content; they are not a permission token.
Absence of decoded content is an explicit app-owned failure view, never a silent empty preview or an implicit fetch.
The generated screen's exhaustive branches cover missing, unsupported, cancelled and closed states, not merely the
successful call.

## Synthetic verification, not format support

The only committed file is `Fixtures/interop-document-preview/res/raw/synthetic_document.txt`, a short synthetic
UTF-8 text with no personal data. `SyntheticDocumentController` reads that fixture through Android resources, checks
its exact bytes and size, and decodes it as bounded plain text. It does not represent a general URI permission
implementation. Missing and unsupported results are classified before display; cancellation prevents a pending load
from becoming ready; close clears the decoded content and disposes the preview. No private document, personal URI,
recipient, remote host or WebView is used.

The real CLI regenerates the fixture for both backends. `python3 -I scripts/check_fixture_compilation.py` stages
its actual Kotlin and synthetic bytes; `:fixtures:compileDebugKotlin` compiles the generated call with the app's
native implementation. `:fixtures:testDebugUnitTest` executes Compose on Robolectric. The three document tests
cover ready/close/disposal, missing/unsupported, and loading/cancel with no stale ready result. These are Native JVM
source/behavior results, not emulator or device evidence.

A PDF or image MIME value can cross the typed metadata boundary, but this change supplies no PDF renderer, image
decoder or claim that such a document opens successfully. An application must add its own implementation and native
verification for those formats. Likewise the example is not a production document picker or permission policy.
Production support needs bounded native decoding, cancellation and lifecycle evidence on each target.

To repeat the Android verification after `swift build`:

```sh
python3 -I scripts/check_fixture_compilation.py
examples/android/gradlew -p examples/android --no-daemon \
  :fixtures:compileDebugKotlin :fixtures:testDebugUnitTest
```

The SwiftUI body is an app-owned iOS sketch only and is not compiled by this Linux fixture gate. ArkTS is generated
and reviewed as source, but is not compiled here: no HarmonyOS command-line toolchain is installed. No iOS or
HarmonyOS native rendering, URI permission, PDF/image decode, device lifecycle or performance result is claimed.
