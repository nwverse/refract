# Native lifecycle, notification and deferred-work contracts

Refract models these capabilities as typed native host boundaries. It does not translate system services into
SwiftUI views, request permission, schedule a notification, post to a recipient or start a background job. The
application owns the implementation on every platform, including policy, persistence and platform lifecycle
observation. The generated code contains only ordinary typed interfaces, parameters and calls.

## Closed source roles

An application declares one of these source-only marker protocols in its iOS support declarations. The generated
input names the concrete application protocol, so the generated interface has the application's name, not a Refract
service registry:

```swift
protocol SyntheticLifecycleHost: RefractLifecycleHost {
    func foreground()
    func background()
}

protocol SyntheticNotificationHost: RefractNotificationHost {
    func present(_ id: String, revision: Int)
    func cancel(_ id: String, revision: Int)
    func confirm(_ id: String, revision: Int)
}

protocol SyntheticBackgroundHost: RefractBackgroundWorkHost {
    func schedule(_ id: String, revision: Int)
    func cancel(_ id: String, revision: Int)
    func confirm(_ id: String, revision: Int)
}
```

The three role signatures are exact and closed. Notification and background requests return `Void`: an invocation
is only a request to the app. It cannot synchronously report scheduling, delivery or completion. `confirm` is an
explicit request for the app to resolve a confirmation boundary, not an implicit consequence of `present`,
`schedule` or a button becoming enabled. Unsupported return values, erased payloads, missing correlation,
additional role methods and mixed roles are `RFHOST001`–`RFHOST003` diagnostics.

A screen accepts the app implementation as a typed input. This is ordinary incremental adoption: no initializer,
host container or global registry is added.

## Lifecycle is not inferred from a view

`RefractScenePhase` is a closed `foreground`/`background` enum. A lifecycle screen declares a typed value and the
two reserved root modifiers:

```swift
struct LifecycleScreen: View {
    let lifecycle: SyntheticLifecycleHost
    @RefractNativeValue var phase: RefractScenePhase

    var body: some View {
        VStack {
            switch phase {
            case .foreground: Text(verbatim: "Synthetic foreground")
            case .background: Text(verbatim: "Synthetic background")
            }
        }
        .refractNativeValue(phase.state)
        .refractOnAppear
        .refractOnDisappear
    }
}
```

Compose emits a normal `DisposableEffect(Unit)` whose entry and `onDispose` call the typed host. ArkUI emits
`aboutToAppear`/`aboutToDisappear`. These report screen presence; they are not proof that the application entered
foreground or background. The app-owned lifecycle implementation must subscribe to the platform's actual
application/scene lifecycle and update the supplied `phase` value. It must not treat navigation appearance alone as
an application lifecycle guarantee. An ordinary `.task`, arbitrary lifecycle closure or notification-looking view
is outside this contract.

## Events, correlation and confirmation

`RefractNotificationEvent` and `RefractBackgroundWorkEvent` are complete, nonoptional value declarations with an
`id: String`, `revision: Int` and a finite `state`. There is no optional missing event, asynchronous stream,
dynamic string discriminator or arbitrary payload. The host always supplies the last known state, including an
explicit `unavailable` state when the capability or permission is absent. `id` is an app-owned opaque identifier,
not a recipient, address or user payload; `revision` orders a replacement of that logical request.

Both roles require these branches, and the frontend's exhaustive switch checks reject omissions:

| Event | Meaning the app is allowed to convey |
| --- | --- |
| `unavailable` | Capability or permission is unavailable; the app owns any permission UX. |
| `accepted` | The app received the request; no scheduling or execution has occurred. |
| `scheduled` | The app explicitly confirms native scheduling, not delivery or execution. |
| `delivered` (notification) | The app explicitly confirms notification delivery. |
| `completed` (background work) | The app explicitly confirms deferred-work completion. |
| `cancelled` | The app explicitly confirms cancellation. |
| `stale` | The event belongs to a superseded id/revision and must not update the current result. |
| `confirmationRequired` | The app requires an explicit, correlated confirmation. |
| `confirmed` | The app explicitly confirms that same correlated request. |

`accepted` and `scheduled` are deliberately distinct. Neither establishes delivery or background execution.
Delivery/completion and confirmation likewise require their own event. A stale event retains its correlation so
the app can discard it rather than accidentally rendering it as a current result.

A screen selects one view of each native input at its root with `.refractNativeValue(event.state)` or
`.refractNativeValue(correlation.id)`. The latter supplies a complete typed `{id, revision}` correlation value;
its `revision` member remains available to every request. It does not create an alternate event source. A screen
that acts on multiple concurrent operations needs separately typed inputs owned by its parent, not a hidden map
or event queue. This first slice intentionally does not implement such a collection.

The notification and background fixtures show unavailable, accepted, scheduled, terminal, cancelled, stale and
confirmation states. Their ids and values are synthetic. No real recipient, notification permission, background
scheduler or work execution is involved.

## iOS source declarations

The reserved names are source contracts, not a linked Refract library. An iOS app declares the closed roles,
values and no-op forwarding helpers in its own source. The following is the reference shape; exact SwiftUI
compilation is not verified on this Linux host:

```swift
public protocol RefractLifecycleHost {}
public protocol RefractNotificationHost {}
public protocol RefractBackgroundWorkHost {}

public enum RefractScenePhase { case foreground, background }
public enum RefractNotificationEventState {
    case unavailable, accepted, scheduled, delivered, cancelled, stale, confirmationRequired, confirmed
}
public struct RefractNotificationEvent {
    public var id: String
    public var revision: Int
    public var state: RefractNotificationEventState
}

@propertyWrapper
public struct RefractNativeValue<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

public extension View {
    var refractOnAppear: some View { self }
    var refractOnDisappear: some View { self }
    func refractNativeValue<Value>(_ value: Value) -> some View { self }
}
```

The app supplies the background-work equivalents. It supplies the property-wrapper initial value in a concrete
screen, typically from its native model, and forwards real lifecycle changes to its lifecycle implementation.
No notification, permission or background API is hidden in these declarations. They are an iOS integration
contract requiring an Apple-toolchain check before production adoption; generator acceptance is not that check.

## Diagnostics and evidence boundary

- `RFHOST001`: unknown or mixed host roles, or a malformed typed host input.
- `RFHOST002`: an incomplete role, arbitrary requirement, erased payload or execution/delivery return value.
- `RFHOST003`: an unbound lifecycle hook or mismatched request, id or revision.
- `RFHOST004`: missing event, duplicate independent event view, or unbound capability input.
- `RFHOST005`: an invalid selected field, correlation read or event usage.

The canonical cases are `Fixtures/interop-native-lifecycle`, `Fixtures/interop-native-notification` and
`Fixtures/interop-native-background-work`. They generate both Kotlin and ArkTS through the real CLI. The Android
fixture manifest compiles all three generated Kotlin files with their native resources. Robolectric Native JVM
tests inject synthetic foreground/background, unavailable, stale, cancelled, accepted, scheduled, completed and
confirmation values into the unmodified generated components, and record the typed host calls.

That evidence is **source generation, Kotlin compilation and Native JVM Compose behavior**. It is not an emulator,
device, real notification delivery, permission grant or background execution claim. ArkTS and iOS source require
their respective toolchains and native hosts before claiming compiler or runtime evidence. No performance
benchmark is implied by this boundary.
