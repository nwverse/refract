# Typed navigation with native hosts

This document covers two bounded navigation contracts:

1. **Typed stack destinations** (`NavigationStack(path:)` + `navigationDestination`), introduced for issue #157 and
   extended to three-level host-owned back/restoration by #221.
2. **Typed tabs and overflow menu actions** (`TabView(selection:)` + `.tabItem`/`.tag` + one `.toolbar` `Menu`),
   implemented for issue #204. See "Typed tabs and overflow menu" below.

Both are root-screen contracts, not a general navigation framework. The same Swift source is ordinary SwiftUI on
iOS; generated Android and HarmonyOS components do not contain a Refract router, registry or navigation runtime.

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

- a same-file generated View with exactly one declared `let model: Protocol` input, passed from the root's model.
  Destination-owned scalar or form `@State` is local to that native back-stack entry and needs no call-site argument;
  a destination-owned `[Route]` path is rejected as a nested stack with `RFNAV003`, because its native callback would
  not be supplied. Use a qualified `NavigationLink` registered with the enclosing graph instead. Any other stored
  input, including a second model or `@Binding`, is rejected rather than omitted from the generated call; or
- a zero-argument declared `RefractNativeView`, implemented by the application on each target through the existing
  typed mapping contract.

This version does not accept cross-file destinations. That is a separate declaration-resolution concern (#152), not
a runtime lookup problem. Payload enums, arbitrary destination objects, dynamic strings, closure destinations,
programmatic path mutation, multiple or nested stacks, incomplete registrations and transition animation modifiers
are build-time errors. A future expansion must define its typed native representation first.

### Multiple levels share the same host operation

A registered destination can push another finite destination without owning a second path. It writes an explicit
enum case in an ordinary `NavigationLink`:

```swift
struct DetailScreen: View {
    let model: DetailModel

    var body: some View {
        VStack {
            Text(model.title)
            NavigationLink("navigation.open.editor", value: Route.editor)
        }
    }
}
```

The enum remains the same `Route` used by the root's `[Route]` path, and `editor` must have an exhaustive typed
branch in the root's `navigationDestination` switch. A qualified value outside a registered destination, an inferred
child value, a model/string payload, an unregistered case or a destination shared by graphs with different host
callbacks is `RFNAV001`/`RFNAV003`. There is no inferred runtime parent route and no `Any` or object destination.
Sheet/alert presentation and dismissal remain owned by #203; tab selection and overflow-menu hosts remain #204.
This graph does not emit either container or reinterpret a modal Boolean as a stack path.

The `Screen.navigation` IR field binds this linked destination to the enclosing graph after all source declarations
are parsed. During that linking step the frontend replaces a qualified link's conventional `path` placeholder with
the actual enclosing operation's `pathName` and preserves its checked `enumName`. The resulting `NavigationLink` and
`Screen.navigation` therefore agree exactly before serialization; Compose requires this equality and never treats
the string `path` as a wildcard. Manual or decoded IR with mismatched fields fails with `RFNAV003`.
The unmerged `allowsEnclosingGraphPathPlaceholder` marker was removed as authority and is no longer serialized. Its
legacy key is accepted only for decoding compatibility and discarded; it cannot waive validation. Older operation
JSON without that key is unchanged.
Only generated Views that actually contain a link receive an `onPathNavigate: (Route) -> Unit` parameter
(the actual source path name is preserved). The exhaustive `NavigationScreenDestinations` switch exposes the same
callback when any branch needs it and forwards it to those branches. Leaf destinations and all two-level #157 APIs
remain unchanged. This is ordinary explicit callback forwarding, not an environment object, singleton, route table
or second stack. `Fixtures/navigation-deep-restoration/` contains the root → detail → editor source and both outputs.
`Tests/RefractComposeTests/Fixtures/navigation-custom-path/` pins the complete generated Kotlin `routePath` callback,
and `Tests/RefractArkUITests/Fixtures/navigation-custom-path/` pins its ArkTS counterpart. The shared frontend resolves
each root or qualified destination link's path and enum from its checked enclosing graph before backend emission.
Compose and ArkUI then require exact link/operation equality, including after JSON decoding: a conventional literal
`path` does not prove frontend provenance. Missing or mismatched graph operations are `RFNAV003`, never a guessed
callback. The same typed path is forwarded by Compose destination switches. This is source-level generation evidence,
not Kotlin or ArkTS compilation.

Native back and restoration are **not** translated into generated state. The generated Kotlin and ArkTS contain no
saved-state bundle, serializer, process-restoration observer or path mutation. Native destination-local state uses
the host toolkit's ordinary saveable/state mechanism at its own back-stack entry. The finite enum is the complete
host route set; the host must register every case and preserve its native saved-state behavior.

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

`Fixtures/navigation-deep-restoration/NativeHost.kt` additionally registers root, detail and editor. Its
`NavigationDeepRestorationTest` uses the real `NavHost`, `NavController`, Compose and `rememberSaveable` on
Robolectric. It checks three-level system-back order, `Activity` recreation retaining the editor entry and its
native saved value, and `NavController.saveState()`/`restoreState()` retaining route order. This is **Native JVM**
evidence, not emulator or device evidence and not a timing benchmark. It verifies the host contract; it does not
prove Android OS process death on a physical device.

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

`Fixtures/navigation-deep-restoration/NativeHost.ets` extends this to three typed destinations, forwarding the
same push callback through the generated destination switch. The application page retains its `NavPathStack` and
integrates its own lifecycle/persistence; no generated component serializes routes. **Restoration on HarmonyOS is
source-level design only, not executed evidence.** No HarmonyOS command-line toolchain is installed in the current
environment; enum-to-name behavior, `@Builder` binding and lifecycle require a real toolchain/device check
before production use. An unsupported host integration must remain native rather than introducing a shim runtime.

## Diagnostics and verification boundary

| Code | Rejected construct | Required alternative |
| --- | --- | --- |
| `RFNAV001` | Malformed stack, link or destination registration | Use the explicit bounded forms above |
| `RFNAV002` | Invalid path ownership, non-Hashable identity or payload destination | Use an empty `[Route]` @State and no-payload `Hashable` enum; pass data through a model |
| `RFNAV003` | Unknown, duplicate, missing or untyped destination/view/link; a destination input or path not supplied by its call | Register every case with a same-file View with one model input plus optional destination-owned scalar/form state, or a declared native component; use qualified links in the enclosing graph instead of a destination-owned path |

The golden corpus includes `navigation-native-destination`, `navigation-host`, `navigation-deep-restoration` and
`navigation-reject-child-untyped`; focused frontend tests cover dynamic links, payload identity, missing or
unregistered destinations and both native outputs. `scripts/check_fixture_compilation.py` stages
optional `NativeHost.kt` and `NativeComponent.kt` files, so `examples/android/fixtures` compiles the host and the
application-owned native escape view with the real navigation library.

What that proves: deterministic dual-backend source generation, typed public entry points, rejected unsupported
input, and Kotlin type checking of the generated components plus the native host. Native JVM tests additionally cover
three-level back order, Activity recreation and explicit controller state restoration as described above. What it
does not prove: SwiftUI or ArkTS compilation, HarmonyOS saved-state behavior, physical-device process death or
transitions, or measured performance. Those remain explicitly separate verification work, not silent claims of this
contract.

## Native sheets and confirmation alerts (issue #203)

The bounded source form is ordinary SwiftUI. `sheet(isPresented:)` accepts a projected Boolean `@State` or `@Binding`
and one content root. `alert(_:isPresented:actions:message:)` accepts a static localized title and message, one
model-action confirmation button and one cancel-role button. Each screen has at most one of each, attached to its
supported root container (not to a Button, Text or other leaf), with distinct Boolean owners. `sheet(item:)`, dynamic
titles, arbitrary action builders, nested modals, detents,
interactive-dismissal policies and transition customization are not silently approximated.

### Android: direct Material 3 modals

A true Boolean calls `ModalBottomSheet` or `AlertDialog`; it does not conditionally lay out a visual substitute.
`onDismissRequest`, cancel and outside/native dismissal all write false through the original local state or binding.
Confirmation first dismisses and then invokes the typed model action. A `LaunchedEffect` scoped to a presented alert
invokes the typed `on<State>Present` callback on each entry, including when a parent changes the binding directly.
There is no global back handler, overlay host, controller registry or application-start initialization. Material 3's
native window/Popup owns focus, modal input, accessibility and system-back dispatch. Sheet generation has a narrow
`@OptIn(ExperimentalMaterial3Api::class)` on the containing component only.

`Fixtures/modal-native-host/NativeModalHostTest.kt` executes the generated Compose on Robolectric (**Native JVM**).
It verifies typed sheet content, the native sheet `Dismiss` accessibility action and reopening; alert title/message
and native button click semantics; cancel; dismissal-before-confirm; and presentation callbacks on open/reopen.
Calling `ComponentActivity.onBackPressedDispatcher.onBackPressed()` did not dismiss the sheet or dialog in this JVM
host. Therefore hardware/system-back behavior remains **unverified on a device**; the generated code deliberately
uses the platform's `onDismissRequest` rather than a generated global back workaround.

### HarmonyOS: bound sheet, application-owned alert UIContext

The root's modifier chain receives `.bindSheet(Boolean, this.<state>SheetContent(), options)`. Its native
`onWillDismiss` invokes `DismissSheetAction.dismiss()` and synchronizes the same Boolean owner. A named `@Builder`
owns sheet content, so it is not inserted as an ordinary Boolean layout branch. The API 12+ references are the
[official bindSheet documentation](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-sheet-transition.md)
and [`@Monitor` documentation](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/state-management/arkts-new-monitor.md).

`AlertDialog.show` is imperative, not a Boolean-bound view modifier. Calling it from `build()` would repeat side
effects during rendering. The generated component instead exposes `on<State>Present` and invokes it from
`aboutToAppear` for initial presentation and from a typed `@Monitor` when the Boolean becomes true. The consuming
app's native host handles that event through `getUIContext().showAlertDialog`, using the localized title/message,
two typed buttons and `onWillDismiss`; `Fixtures/modal-native-host/NativeHost.ets` is the complete example. The
host owns dialog focus, accessibility, back and dismissal; no custom overlay, dialog controller or runtime is
introduced. See the [official AlertDialog contract](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-methods-alert-dialog-box.md).
The generated `@Event` default follows the existing binding-event convention; production hosts must supply it when
using this alert rather than assume that the default presents anything.

ArkTS is **source-level generation and host-contract evidence only**. No authorized HarmonyOS compiler or runtime
was available, so `@Builder`, `@Monitor`, dismissal timing, accessibility and actual back behavior are unverified.
iOS compilation and native presentation are likewise **not verified on macOS** here. The Swift input itself uses
ordinary SwiftUI sheet/alert APIs; no iOS shim or generated host replaces them. NavigationStack push/pop remains
#157's separate host contract; tabs/menus and focus/IME are not part of this modal slice.

### Modal diagnostics

| Code | Rejected construct | Required alternative |
| --- | --- | --- |
| `RFMODAL001` | Item sheets, missing/invalid Boolean ownership, malformed sheet content | Use a distinct declared Boolean `@State`/`@Binding` and one bounded content root |
| `RFMODAL002` | Unsupported alert title/message/action shape or dynamic text | Use localized static text, one model-action confirmation and one cancel-role button |
| `RFMODAL003` | Nested/repeated modal hosts, shared state or generated-event name collision | Keep one sheet and one alert with distinct owners on a root host; rename conflicting inputs |

Generation is atomic on these diagnostics. `Fixtures/modal-sheet-state` additionally pins local-state dismissal
and preservation of ordinary root modifiers on both sides of `.sheet`. Neither Kotlin compilation nor JVM interaction
is a performance measurement; no benchmark claim is made for this slice.
## Typed tabs and overflow menu

The tab contract is deliberately narrower than SwiftUI's `TabView`. It covers a finite, statically typed tab
container with an optional bounded overflow menu. It does **not** cover arbitrary navigation graphs, adaptive or
sidebar tab styles, drawers, per-tab navigation stacks or payload selections; those remain build-time diagnostics
(`RFNAV401`–`RFNAV404`), never a silent approximation. An iOS tab is not an Android drawer, and generated code
never substitutes one container for another.

### Source contract

```swift
enum HomeTab: Hashable {
    case overview
    case activity
}

struct OverviewScreen: View {
    var body: some View { Text("tab.overview.body") }
}

struct ActivityScreen: View {
    var body: some View { Text("tab.activity.body") }
}

struct HomeTabsScreen: View {
    let model: OverviewModel
    @State private var tab: HomeTab = .overview

    var body: some View {
        TabView(selection: $tab) {
            OverviewScreen()
                .tabItem { Label("tab.overview", systemImage: "gear") }
                .tag(.overview)
            ActivityScreen()
                .tabItem { Label("tab.activity", systemImage: "person") }
                .tag(.activity)
                .toolbar {
                    ToolbarItem {
                        Menu {
                            Button("menu.refresh") { model.refresh() }
                            Button("menu.reset") { model.reset() }
                        } label: {
                            Label("menu.more", systemImage: "checkmark")
                        }
                    }
                }
        }
    }
}
```

Rules:

- The selection is exactly one `@State private var tab: HomeTab = .overview` over a local no-payload `Hashable`
  enum. Scalar or `@Binding` selections, payload enums and non-`Hashable` enums are `RFNAV402`.
- Each direct child is a **zero-argument same-file generated View** with `.tabItem { Label("key", systemImage:) }`
  and `.tag(.case)`. Destinations must cover every enum case exactly once, in declaration order (`RFNAV403`).
  A tab with stored inputs is rejected in this slice: a tab screen that needs data should read it from its own
  environment/model in a future, separately typed expansion, not from an untyped closure.
- Tab icons reuse the typed `symbols` mapping (`materialIcon`/`drawable` on Android, `media` on HarmonyOS), exactly
  like `Image(systemName:)`. An unmapped symbol is a build-time diagnostic, never a guessed drawable.
- At most one `.toolbar { ToolbarItem { Menu { ... } label: { Label(...) } } }` is accepted, on any one tab child.
  Menu actions are localized `Button`s whose bodies call **one declared model method** (`RFNAV404`); local state
  mutations, closures and arbitrary handlers are not menu actions.
- `sidebarAdaptable` tab styles, `Drawer`, `NavigationSplitView`, nested `NavigationStack` inside tabs and other
  container styles are unsupported and diagnosed.

### Generated native entry points

The source `@State` selection declares iOS ownership and is **not** translated into a second Android or HarmonyOS
selection owner. The generated component is a controlled component:

```kotlin
@Composable
public fun HomeTabsScreen(
    model: OverviewModel,
    tab: HomeTab,
    onTabChange: (HomeTab) -> Unit,
    modifier: Modifier = Modifier,
)

@Composable
public fun HomeTabsScreenDestinations(tab: HomeTab, modifier: Modifier = Modifier)
```

Android lowers the tab bar to Material 3 `NavigationBar`/`NavigationBarItem`, whose `selected` parameter carries the
native selected/role accessibility semantics, and the overflow menu to `IconButton` + `DropdownMenu`/
`DropdownMenuItem`. The icon-only overflow button keeps the localized `menu.more` title as its
`contentDescription`, so the affordance is announced by screen readers. `HomeTabsScreenDestinations` is a complete
`when` over the enum calling each zero-argument generated screen. The host owns the selected tab, back behavior and
per-tab lifecycle; there is no generated router, `NavController`, drawer or second selection `remember`.

ArkTS emits `@Require @Param tab: HomeTab` and `@Event onTabChange`, a `Tabs`/`TabContent` container whose `index`
is derived from the host selection through a typed getter (no parallel `@Local` index), a typed `@Builder` tab bar
carrying the selected state, and a `bindMenu` overflow whose items call the same typed model actions. There is no
`NavPathStack`, `SideBarContainer` or runtime dispatch.

### Android host and verification

`Fixtures/navigation-tabs-menu/` is the golden case. Its regenerated Kotlin is staged and compiled by
`scripts/check_fixture_compilation.py` + `:fixtures:compileDebugKotlin`, like every manifest fixture.

Real Android behavior is verified by
`examples/android/fixtures/src/test/java/com/example/refract/tabs/GeneratedTabsMenuTest.kt`, which runs the
**actual CLI-generated** `HomeTabsScreen` on **Native JVM (Robolectric)** with a host-owned `selectedTab`:

- selected tab drives `assertIsSelected`/`assertIsNotSelected` and the visible destination;
- a tab click reaches `onTabChange` and switches the typed destination;
- a host-driven selection change updates the generated screen;
- the overflow affordance (found by its generated content description) opens the menu and each item calls the
  typed model method exactly once.

These are Native JVM results, not emulator or device results, and make no visual-parity or performance claim.

### iOS and HarmonyOS verification boundary

On iOS the same source is ordinary SwiftUI: `TabView(selection:)` owns the selection through the `@State` binding,
`.tabItem`/`.tag` provide the tab items and `.toolbar` provides the overflow menu. iOS 16 or later is required. No
macOS/Xcode build was run for this slice, so iOS compilation and real selection/back behavior are unverified here
and must not be inferred from the Kotlin tests.

The generated ArkTS is reviewed as source only. No HarmonyOS command-line toolchain is installed in this
environment, so `Tabs` index binding, `bindMenu` behavior and page lifecycle need a real toolchain/device check
before production use. An unsupported host integration must remain native rather than introducing a shim runtime.

### Diagnostics

| Code | Rejected construct | Required alternative |
| --- | --- | --- |
| `RFNAV401` | Malformed `TabView`, tab item, tag or unsupported tab modifier | Use the bounded `TabView(selection:)` + `.tabItem`/`.tag` form |
| `RFNAV402` | Invalid selection ownership, scalar/payload/non-Hashable selection | Use `@State private var tab: Tab = .case` over a no-payload `Hashable` enum |
| `RFNAV403` | Non-exhaustive, out-of-order, duplicated or input-carrying tab destination | Cover every case once, in order, with a zero-argument generated View |
| `RFNAV404` | Unsupported toolbar/menu shape or non-model menu action | One `ToolbarItem`/`Menu` with localized model-action `Button`s |
