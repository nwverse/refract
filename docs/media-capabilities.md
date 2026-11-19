# Typed native playback, camera and system-share capability contracts

`Fixtures/interop-media-capabilities/` defines a bounded source contract for three independently named application-owned
native components: playback, camera capture and system sharing. It does not implement a player, camera, codec, sensor,
permission prompt, share sheet, URI resolver or recipient picker. A real application supplies and verifies its own
platform implementation through the existing `RefractNativeView` mapping.

## Closed ABI and explicit state

Each component accepts exactly these parameters, in order:

```swift
let identifier: String
let revision: Int
let onCancel: () -> Void
```

`identifier` is an app-owned synthetic correlation value, not a media URI, file handle, decoded payload or recipient.
`revision` lets the native implementation scope replacement and disposal. `onCancel` accepts only the existing checked
zero-argument model action; Compose emits `() -> Unit` and ArkTS emits `() => void`. There is no arbitrary closure,
content object, permission object or platform handle in the ABI. The schema-1 mapping uses `type: action`; the compact
scalar mapping form does not accept this callback.

The generated screens use separate finite states for each capability: `unavailable`, `permissionRequired`,
`permissionDenied`, `approvalRequired`, `ready` and `cancelled`. The first three branches never place a native
capability component. `approvalRequired` exposes explicit typed request-approval and cancellation model actions;
neither action returns a permission result or grants access. `ready` is only an input state selected by the app after
it has independently decided to supply its native implementation. `cancelled` is explicit rather than an empty player,
camera preview or share sheet. The generator's exhaustive enum checks reject omission of these states.

The three components intentionally do not share a dynamic string discriminator. Each has a statically mapped target
symbol and an exact parameter signature. A different implementation or per-platform variation remains application
code under goal 5; the generator never performs runtime lookup or translates a system service.

## Permission, approval and cancellation ownership

The app alone decides capability availability, requests platform permission where applicable, shows its own approval
UI, validates content and recipients, and starts or cancels native work. No generated call requests permission, opens
a URI or launches a system share UI. In particular, `permissionRequired` and `permissionDenied` for sharing are
app-defined policy states, not an assertion that every platform has a sharing permission.

An approval request means only "ask the app to handle approval." It cannot synchronously report that permission was
granted or that playback, capture or sharing succeeded. Cancellation invalidates the app-owned pending request. A late
approval must be matched to the still-pending kind, identifier and revision and discarded after cancellation or
replacement; it must not select `ready`. The synthetic controller compares all three correlation fields and requires both pending and
current phases to remain `approvalRequired`; a superseded identifier, kind or revision cannot accept an old approval.
Leaving a ready native component lets its app-owned implementation release its resources through normal native
disposal; the fixture observes that callback only and does not claim to release real hardware or media resources.
The generator does not invent a second timer, cancellation queue or lifecycle owner.

## Synthetic evidence and rejected payloads

The actual CLI regenerates `Expected.kt` and `Expected.ets`. Both contain the same three closed state machines and
direct typed native calls. `interop-media-capability-reject` rejects an undeclared `recipient` parameter with
`RFNATIVE002` before either backend writes output. Additional generator tests reject a missing absence state and an
arbitrary permission closure; neither creates a fallback component or target expression.

`examples/android/fixtures/src/native/java/com/example/refract/media/` contains only a static Compose surface and a
synthetic controller. It imports no Android media, camera, intent, URI or permission API. Native JVM Compose tests
exercise unmodified generated screens for explicit absence, permission states, approval, cancellation, a stale approval
after camera cancellation, same-revision replacement of the pending identifier or capability kind, share cancellation
and native disposal. Those two replacement tests keep the revision unchanged to prove that revision alone cannot
authorize a late result. No media bytes, capture data, personal URI, recipient or permission dialog is used.

Run after a bounded `swift build`:

```sh
python3 -I scripts/check_fixture_compilation.py
examples/android/gradlew -p examples/android --no-daemon \
  :fixtures:compileDebugKotlin :fixtures:testDebugUnitTest
```

The result is **dual-backend source generation, actual Kotlin compilation and Native JVM behavior**, not an emulator,
device, iOS or HarmonyOS capability result. The app-owned iOS bodies are ordinary SwiftUI sketches and were not
compiled by this Linux gate. ArkTS is generated and reviewed as source, but its native component implementation,
compiler and lifecycle are **not verified** here. No real playback, camera capture, permission, system share,
recipient selection, URI access, media codec, device lifecycle or performance claim follows from this fixture.
