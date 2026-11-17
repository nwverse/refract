# Typed navigation with native hosts

This is the bounded navigation contract implemented for issue #157. It covers a root screen and typed destinations,
not a general navigation framework. The same Swift source is ordinary SwiftUI on iOS; generated Android and HarmonyOS
components do not contain a Refract router, registry or navigation runtime.

## Source contract

A navigation root has one local empty path array and a source-owned finite destination enum:

```swift
enum Route: Hashable {
    case detail
}

protocol DetailModel: RefractModel {
    var title: String { get }
}

struct DetailScreen: View {
    let model: DetailModel

    var body: some View {
        Text(model.title)
    }
}

struct NavigationScreen: View {
    let model: DetailModel
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                NavigationLink("navigation.open", value: .detail)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .detail:
                    DetailScreen(model: model)
                }
            }
        }
    }
}
```

The enum must conform only to `Hashable` and have no raw values or associated values. Its cases, not strings supplied
at run time, are the complete destination identity. `navigationDestination` applies to the root content in the stack,
and its `{ route in switch route ... }` closure lists every case exactly once. Each branch is either:

- a same-file generated View with exactly one declared `let model: Protocol` input, passed from the root's model; or
- a zero-argument declared `RefractNativeView`, implemented by the application on each target through the existing
  typed mapping contract.

This version does not accept cross-file destinations. That is a separate declaration-resolution concern (#152), not
a runtime lookup problem. Payload enums, arbitrary destination objects, dynamic strings, closure destinations,
programmatic path mutation, multiple or nested stacks, incomplete registrations and transition animation modifiers
are build-time errors. A future expansion must define its typed native representation first.

The localized link title uses the normal resource contract. Root content may use the existing supported containers;
a `NavigationLink` value must be a static case of the stack's enum. There is no untyped destination callback.

## Generated native entry points

The `@State` path declares iOS ownership and is **not** translated into a second Android or HarmonyOS back stack.
Instead, generated components expose ordinary typed native calls:

```kotlin
@Composable
public fun NavigationScreen(
    model: DetailModel,
    onPathNavigate: (Route) -> Unit,
    modifier: Modifier = Modifier,
)

@Composable
public fun NavigationScreenDestinations(
    destination: Route,
    model: DetailModel,
    modifier: Modifier = Modifier,
)
```

The root calls `onPathNavigate(Route.detail)` from a normal Material 3 button. The destination component has a
complete `when` over the enum and calls `DetailScreen` or the mapped native component directly. ArkTS emits the
corresponding enum, `@Event` callback and `if`/`else if` destination component. There is no dynamic map, `Any`,
reflection, target-language template or generated `NavController`/`NavPathStack`. Generated code never intercepts
back, mutates the path, adds a lifecycle observer or introduces a host/transition wrapper: its components retain the
same surrounding native lifecycle as directly hand-written composables/components.

### Android host: controller and back stack stay native

`Fixtures/navigation-host/NativeHost.kt` is compiled with the real `navigation-compose` dependency alongside the
regenerated Kotlin. The essential shape is:

```kotlin
val controller = rememberNavController()
NavHost(navController = controller, startDestination = "home") {
    composable("home") {
        NavigationScreen(model = model, onPathNavigate = { destination ->
            controller.navigate(destination.name)
        })
    }
    composable(Route.detail.name) {
        NavigationScreenDestinations(destination = Route.detail, model = model)
    }
}
```

The host registers the same finite case set with stable `Route.<case>.name` strings. The strings are host-side
`NavHost` keys, not a Refract destination registry and not values accepted from the source at run time. The host owns
push, pop, Android system back, saved state and destination lifecycle. No back interception or parallel stack is
generated. The host chooses the existing native transition policy; this contract does not claim a shared animation
mapping.

`Fixtures/navigation-native-destination/NativeHost.kt` also compiles the mapped zero-argument `NativeDetail()` escape hatch. A
project can instead register an entirely hand-written composable for that enum case; it need not call the generated
destination switch for a screen that has no shared implementation.

### iOS host: the same source uses SwiftUI directly

On iOS, `NavigationStack(path:)` receives the actual `@State [Route]`, `NavigationLink(value:)` appends a typed value,
and `navigationDestination` selects the same model-backed destination. The app's surrounding `WindowGroup`, scene and
lifecycle are unchanged. A native iOS screen remains available through `RefractNativeView`'s ordinary SwiftUI body or
as a native sibling destination. iOS 16 or later is required for these APIs.

`Fixtures/navigation-host/Input.swift` is the two-screen source of truth. Its generated ArkTS is checked in as
`Expected.ets`; iOS needs no generated source. No macOS/Xcode build was run for this slice, so iOS compilation and
actual back/lifecycle behavior remain unverified here and must not be inferred from Kotlin tests.

### HarmonyOS host: `NavPathStack` stays native

`Fixtures/navigation-native-destination/NativeHost.ets` is the corresponding native host shape: an application-owned `NavPathStack`
receives `pushPath` from the generated callback, and its `navDestination` builder calls the generated destination
component for the finite case names. The host owns pop, system back and page lifecycle. This source is reviewed as a
contract example, **not** as verified ArkTS compilation. No HarmonyOS command-line toolchain is installed in the
current environment; enum-to-name behavior, `@Builder` binding and lifecycle require a real toolchain/device check
before production use. An unsupported host integration must remain native rather than introducing a shim runtime.

## Diagnostics and verification boundary

| Code | Rejected construct | Required alternative |
| --- | --- | --- |
| `RFNAV001` | Malformed stack, link or destination registration | Use the explicit bounded forms above |
| `RFNAV002` | Invalid path ownership, non-Hashable identity or payload destination | Use an empty `[Route]` @State and no-payload `Hashable` enum; pass data through a model |
| `RFNAV003` | Unknown, duplicate, missing or untyped destination/view/link | Register every case with a same-file typed model destination or declared native component |

The golden corpus includes `navigation-native-destination` and `navigation-host`; focused frontend tests cover dynamic links,
payload identity, missing registrations and both native outputs. `scripts/check_fixture_compilation.py` stages
optional `NativeHost.kt` and `NativeComponent.kt` files, so `examples/android/fixtures` compiles the host and the
application-owned native escape view with the real navigation library.

What that proves: deterministic dual-backend source generation, typed public entry points, rejected unsupported
input, and Kotlin type checking of the generated components plus the native host. What it does not prove: SwiftUI or
ArkTS compilation, rendered screenshots, device transitions, saved-state restoration, or measured performance. Those
remain explicitly separate verification work, not silent claims of this contract.
