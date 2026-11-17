# Bounded remote images through typed native components

The built-in `Image` remains a static application-resource view. A remote image is an app-owned
`RefractNativeView`, not a second built-in whose loading, cache and failure policies would be invented by the
generator. There is no shared image runtime and no target-source template.

## Typed source boundary

```swift
struct RemoteImage: RefractNativeView {
    let url: String
    let placeholder: Image
    let failure: Image
    let contentDescription: LocalizedStringKey
    let loader: RemoteImageLoader

    var body: some View { /* The app's ordinary SwiftUI implementation. */ }
}

struct ProfileImage: View {
    let url: String
    let loader: RemoteImageLoader

    var body: some View {
        RemoteImage(
            url: url,
            placeholder: Image("profile_placeholder"),
            failure: Image("profile_unavailable"),
            contentDescription: "profile.photo.description",
            loader: loader
        )
    }
}
```

The `Image` and `LocalizedStringKey` types are accepted only as stored parameters of a native-component declaration.
They do not become supported model, state, binding, enum-payload or arbitrary native values. An image argument is
exactly `Image("lowercase_resource_name")`; system symbols, arbitrary constructors, computed resource names and
strings used in place of images are `RFNATIVE002` diagnostics. The resource name is shared by Android and HarmonyOS
and must exist in the app's resource catalog. A localized text argument is a literal resource key validated against
both native string catalogs. URLs remain declared `String` inputs, so a normal model or screen input can supply them;
Refract does not evaluate or fetch them at generation time. `RemoteImageLoader` is an explicitly declared application
protocol: the caller injects it into both the generated screen and native component. Constructing a loader inside the
view, passing an unrelated object or omitting the injection is `RFNATIVE002`; there is no default client or service
locator. Both target mappings bind it to their app-owned `RemoteImageLoader` interface.

The fixture's SwiftUI body is the consumer's iOS implementation. It validates HTTPS input and uses `AsyncImage`;
its source-level behavior is not translated to the other platforms. The Android and HarmonyOS entries supply the
native implementation through `refract.json`, with `image` parameters becoming drawable/media resource values and
`stringKey` becoming a resolved localized string. The generator adds no networking library or import.

## Native lifecycle contract

A conforming native implementation must:

- accept only an absolute HTTPS URL with a nonempty host and no user information; an application may further
  restrict its permitted hosts. The reference implementation rejects malformed input before asking its loader for a
  request. It is not a substitute for an app's network security policy or an SSRF defense;
- show the placeholder while loading, the successfully decoded image only for the current request, and the failure
  resource for malformed input or loader/decode failure;
- use the URL as the request identity. Changing it cancels the old request, restores the placeholder, and prevents
  an old completion from overwriting the new result;
- cancel loading when the component leaves composition or its equivalent native lifecycle. A cancellation is not an
  error and does not replace the current image with a stale failure;
- preserve the localized content description on loading, success and failure branches, rather than describing a
  transient error implementation detail;
- keep request policy, networking, response-size limits and any application cache in app-owned code. No global cache,
  implicit network client, arbitrary target source or Refract initialization is introduced.

The example Android implementation takes an application-provided `RemoteImageLoader`. Its Native JVM Compose tests use a controlled
in-memory loader only: they verify composition lifecycle, cancellation and state transitions, not real network
access, TLS, HTTP caching or device performance. The component rejects invalid input before invoking the loader,
bounds encoded bytes to 8 MiB and decoded dimensions to 16,777,216 pixels, and cancels in-flight work when its URL
or loader changes. These application limits are examples, not generator-enforced network security.

`Fixtures/interop-remote-image` proves dual-backend typed lowering; its negative counterpart rejects malformed
construction. Android compilation and the local native test exercise the actual CLI-generated fixture. The native
sources live in the fixture module's `src/native` source set, not the generated staging tree that
`check_fixture_compilation.py` deletes on each run. The script additionally stages the exact generated call and
its resources into the app's ignored `src/fixtureTest` tree so Native JVM tests use the real application resource
namespace. To repeat the verification after `swift build`:

```sh
python3 -I scripts/check_fixture_compilation.py
examples/android/gradlew -p examples/android --no-daemon \
  :fixtures:compileDebugKotlin :app:compileDebugKotlin :app:testDebugUnitTest --tests example.app.RemoteImageTest
```

The Gradle task stages the already-resolved public Robolectric runtime and sets `robolectric.offline=true`. No test
contacts a remote host. The XML result records ten Native JVM tests; this is neither an emulator nor device run.

HarmonyOS ArkTS and the iOS SwiftUI body are not compiled on this Linux machine. The HarmonyOS implementation must prove
about-to-disappear cancellation and equivalent state behavior with its authorized native toolchain before claiming
runtime parity. iOS must likewise be checked on macOS with the consuming app's loader and accessibility settings.
