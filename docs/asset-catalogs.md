# Typed application asset catalogs

Refract can resolve a small, statically named subset of an application's image, font and raw resource catalogs. The
application owns every file, its packaging, native registration and content parsing. Refract reads only bounded
resource metadata while generating source; it never copies assets, serves files or adds a runtime. Android XML
images are the one structural exception: their XML root is parsed, with external entities disabled, to require a
Compose-compatible `vector` drawable. Font, raw and raster-image contents are not read by the generator.

## Configuration

Opt in independently in each platform's existing `resources` object:

```json
"android": {
  "resources": {
    "className": "example.app.R",
    "catalog": "res/values/strings.xml",
    "assetCatalog": "res",
    "strings": { "assets.logo.description": "assets_logo_description" }
  }
},
"harmonyOS": {
  "resources": {
    "namespace": "app",
    "stringTable": "string",
    "catalog": "resources/base/element/string.json",
    "assetCatalog": "resources",
    "strings": { "assets.logo.description": "assets_logo_description" }
  }
}
```

The root is relative to `refract.json` and is exactly `res` on Android or `resources` on HarmonyOS. This is not a
configurable search path. Every referenced resource must have a base entry on **both** platforms, under the native
kind directory. Resource names are lowercase ASCII letter-led identifiers containing only lowercase letters, digits
and underscores. The HarmonyOS namespace must be `app`, and Android uses the declared fully qualified application
`R` class even when generated Kotlin has another package.

Only real, non-symbolic-link root/group directories and regular files are accepted. No path, glob, nested raw file,
URL, resource-name expression, runtime lookup or `Resources.getIdentifier` is supported. A missing root or base file,
an unknown extension, ambiguous files, a wrong kind, an empty file or an excessive file is an `R.asset.*` build-time
diagnostic. Images/raw files are bounded at 16 MiB and fonts at 4 MiB; this is a packaging bound, not a claim that
arbitrary encoded dimensions or parsed content are safe. The consuming app remains responsible for decode bounds.

Without `assetCatalog`, existing mappings retain their previous native-reference behavior. The option therefore does
not force a resource-layout migration on existing remote-image components or design-token mappings. When either
platform opts in, all assets used by the new typed paths require both native catalogs; there is no one-platform
fallback.

## Images and accessibility

Use ordinary SwiftUI with an explicit localized label for meaningful images:

```swift
Image("app_logo", label: Text("assets.logo.description"))
```

Compose receives `painterResource(example.app.R.drawable.app_logo)` and a localized `contentDescription`; ArkUI
receives `$r('app.media.app_logo')` and `.accessibilityText($r('app.string.assets_logo_description'))`. The string
key must exist in both existing string catalogs. An image without `label:` remains decorative (`contentDescription =
null` and no ArkUI accessibility text). `Image(systemName:)` remains the separately mapped symbol contract, not an
implicit entry in the application asset catalog.

The supported qualified image directories are deliberately bounded:

| Logical variant | Android | HarmonyOS |
| --- | --- | --- |
| Base | `res/drawable/` | `resources/base/media/` |
| Dark | `res/drawable-night/` | `resources/dark/media/` |
| ldpi | `res/drawable-ldpi/` | `resources/ldpi/media/` |
| mdpi | `res/drawable-mdpi/` | `resources/mdpi/media/` |
| hdpi | `res/drawable-hdpi/` | `resources/xldpi/media/` |
| xhdpi | `res/drawable-xhdpi/` | `resources/xxldpi/media/` |
| xxhdpi | `res/drawable-xxhdpi/` | `resources/xxxldpi/media/` |

Each declared variant must exist on both platforms. Dark and independent density variants may coexist; combined
qualifiers and locales are not inferred. Android accepts PNG/JPEG/WebP/GIF or a `<vector>` drawable (an SVG
root is not a Compose-compatible drawable); HarmonyOS accepts its native PNG/JPEG/WebP/GIF/SVG/BMP media files. Their encoded formats need not be identical, but the logical resource
name and qualifiers must match. Refract does not rewrite theme resources or select dark mode: native configuration
selection remains in the platform resource loader. Semantic colors, typography tokens and interaction states belong
to `docs/mapping.md` and the theme workstream, not this binary catalog.

## Fonts

An application-registered font family can be requested on `Text`:

```swift
Text("assets.title")
    .font(.custom("app_body", size: 16, relativeTo: .body))
```

Android packages `res/font/app_body.ttf` or `.otf` and emits a direct `FontFamily(Font(example.app.R.font.app_body))`
plus `16.sp`. HarmonyOS packages `resources/rawfile/app_body.ttf` or `.otf` and emits `.fontFamily('app_body')`
plus `.fontSize(16)`. The registered family name is the validated catalog name; the file itself is not a
`$r('app.font...')` resource. Font files are unqualified; both platform font loaders and dynamic font scaling remain native.
A family must be registered by the application where its toolchain requires registration: ArkUI does not register a
custom family merely because a font file exists. Refract emits no `loadFontSync`, startup hook, global registry or
font-file read. The native compilation contract does not by itself prove that a family is registered or rendered.

The fixture also includes `HarmonyFontRegistration.ets` as an application-owned registration example; it is not
compiled on Linux and is never called implicitly by generated code.

The size is a bounded integer from 1 through 256, and the only supported relative style is `.body`; arbitrary text
style expressions and fixed pixel sizes are rejected. Compose uses `sp` and ArkUI uses its font-pixel (`fp`) numeric
size, so the platform user's font preference still applies. This custom-family form is separate from semantic
`DesignTypography` tokens; it does not replace or hardcode a theme's existing text style.

## Raw assets through app-owned native components

A raw asset is a typed `RefractNativeView` parameter, never a general `String`, a model value or a filesystem path:

```swift
struct AppPolicyDocument: RefractNativeView {
    let document: RawAsset
    var body: some View { /* The app's ordinary iOS resource implementation. */ }
}

AppPolicyDocument(document: RawAsset("privacy_policy"))
```

Declare `document` as `rawAsset` in both native-component mappings. Android emits `R.raw.privacy_policy`; the app's
`@RawRes document: Int` component may use `openRawResource` with its own decoding/size policy. HarmonyOS emits
`$rawfile('privacy_policy.json')` as the native `Resource` input; the app owns its resource-manager read and parser.
The source-side `RawAsset` declaration and ordinary SwiftUI implementation are supplied by the consuming app on iOS;
Refract does not generate that type or turn the marker body into Android/ArkTS code. The fixture includes
`consumer/IOSRawAsset.swift` as a minimal consumer-owned declaration and packaging example; it is not part of the generator
or a library linked by native applications.

Use one unqualified base file with the same lowercase name and extension on both platforms. Android accepts a flat
`res/raw/name.json|txt|bin|svg|pdf` file; HarmonyOS uses `resources/rawfile/name.ext`. Nested paths, qualified raw
variants and arbitrary file extensions are rejected. The generator validates metadata only; raw content, business
schema and file access are not translated. There is no equivalent of a built-in `RawAsset` SwiftUI view on iOS and no
generated native consumer.

Remote images and their URL/cancellation/loader contract are unchanged and documented in `docs/remote-images.md`.
A local catalog reference never creates a network request, cache or remote-image loader.

## Verification and limits

`Fixtures/resource-typed-assets/` contains an ordinary image, paired dark/xhdpi images, a licensed synthetic font,
raw JSON and an app-owned Android raw consumer. Its Kotlin and ArkTS are actual CLI-generated golden output. The
missing-resource counterpart and `AssetCatalogTests` cover missing base resources, kind/extension errors, qualifier
parity, unsafe paths/symlinks, empty files and raw filename drift.

Run the actual resource and Kotlin compilation plus the labelled Native JVM tests with:

```sh
python3 -I scripts/check_fixture_compilation.py
examples/android/gradlew -p examples/android --no-daemon \
  :fixtures:compileDebugKotlin :app:compileDebugKotlin \
  :app:testDebugUnitTest --tests example.app.TypedAssetTest
```

The Native JVM tests inspect the exact generated call, localized image semantics, night resource selection, native
font scaling and application-owned raw reading. This is not emulator/device evidence and not a cross-platform
screenshot or performance claim. The synthetic DejaVu Sans fixture and its license are included solely to test native
font loading; it does not establish a project typography choice.

The Linux environment cannot compile the iOS SwiftUI implementation or ArkTS. HarmonyOS font registration, raw
resource behavior and accessibility require the authorized HarmonyOS toolchain and a native test target. iOS catalog
packaging, `RawAsset` ownership and dynamic-type behavior require macOS/Xcode. Those are explicit unverified
boundaries, not silent fallback behavior.
