# Adaptive window-size alternatives

This slice supports exactly two layout alternatives for one source screen. It is not a device classifier, a responsive
runtime, or a second design system. The existing typed enum/switch Builder and IR are the only branch representation.

## Source contract

```swift
enum WidthSizeClass {
    case compact
    case expanded
}

struct AdaptiveSettingsScreen: View {
    let model: AdaptiveSettingsModel
    let widthSizeClass: WidthSizeClass
    @Binding var notificationsEnabled: Bool
    @Binding var displayName: String

    var body: some View {
        switch widthSizeClass {
        case .compact:
            VStack { /* the same model and controls */ }
        case .expanded:
            HStack { /* the same model and controls, in two panes */ }
        }
    }
}
```

`WidthSizeClass` is reserved for this contract. It must contain exactly `compact` and `expanded`, without raw values,
payloads or inheritance. The immutable input must be named `widthSizeClass`. Both cases are required exactly once;
there is no `default` that could conceal a new platform class. A screen using this input has one root width-class
switch. Ordinary declared enums retain their existing behavior.

The input is **not** a raw pixel width, a device type, a fold state, a font scale or a theme token. The source does
not say "phone" or "tablet": the host's platform classifier makes that contextual decision. Compact and expanded
branches use the same model, bindings and control semantics, with layout alternatives authored in the existing
SwiftUI subset. Typography, spacing, color and component tokens still belong to the application's design system.

Local `@State` remains in the enclosing component, not inside either branch. On Compose it is the same `remember`
state across changes of the native size-class parameter. ArkUI keeps it in the same `@Local` property. A screen's
draft that must also survive its native host removing the destination on push/pop is an explicit `@Binding` owned by
that host (Compose uses `rememberSaveable` in the example); `remember` alone is not a saved-state contract. Text changes
remain native `sp`/`fp` behavior and do not change the selected width class. Scroll, focus and IME ownership are not
silently reconstructed by this layout contract; their independent contracts and limits still apply.

`RFADAPT001` rejects a malformed class, wrong input ownership or a width-class input used without the bounded switch.
`RFADAPT003` rejects combining it with the source `NavigationStack` root: a pushed destination cannot be replaced by a
layout resize. The native host owns measurement, model lifetime, navigation and back, as in `docs/navigation.md`.

## Native host ownership

### Android

The generated parameter is `androidx.compose.material3.windowsizeclass.WindowWidthSizeClass`, not a second enum or
pixel threshold. `Compact` selects compact; both `Medium` and `Expanded` select expanded because the source provides
only two alternatives. The generated root preserves its ordinary caller `Modifier` and emits an `if`/`else`; no
activity lookup, listener, configuration observer or state mirror is generated.

The host calls Material3's `calculateWindowSizeClass(activity)` from composition and passes `.widthSizeClass` to the
generated component. It observes configuration changes and recalculates on native resize, including fold and
multi-window changes. `material3-window-size-class` is an ordinary platform SDK dependency; its API currently requires
`ExperimentalMaterial3WindowSizeClassApi` opt-in. That annotation belongs in the native host, not hidden in generated
screens. `Fixtures/adaptive-window-size/NativeHost.kt` compiles the real calculation and the one native `NavHost`
with the exact CLI-generated components.

### iOS

The same Swift file uses ordinary SwiftUI. The app supplies its `UserInterfaceSizeClass` through a native host, for
example a generic `AdaptiveHost<Content: View>` with `@Environment(\.horizontalSizeClass)` and an initializer taking
the shared content/model. It selects `.compact` or `.expanded` (including `nil`) without changing the source enum.
SwiftUI owns re-evaluation, Dynamic Type and the surrounding `NavigationStack`; no iOS code is generated.

This slice's uniquely named `examples/shared/AdaptiveSettings.swift` is the canonical
`Fixtures/adaptive-window-size/Input.swift` byte-for-byte. The example project compiles that same source and the
app-owned host is registered in the project. macOS/Xcode compilation and iOS rendering were not run in this Linux
environment, so those remain source-only contracts rather than claimed simulator or device evidence.

### HarmonyOS

The generated `@ComponentV2` receives `@Param widthSizeClass: WidthSizeClass` and retains ordinary `if`/`else if`
branches. The native host owns a `GridRow` with platform breakpoints `["600vp", "840vp"]` and
`BreakpointsReference.WindowSize`, and updates an app-owned observed size-class input from `onBreakpointChange`.
`xs`/`sm` map to compact; `md`/`lg`/`xl`/`xxl` map to expanded. This uses the window, not physical device pixels or
a model name. A host that embeds the component in a smaller pane may deliberately use `ComponentSize` and own that
mapping; the generated component does not guess.

`NativeHost.ets` records the typed host shape. **It is source-only evidence**: no authorized HarmonyOS command-line
toolchain or rendering target is installed, so ArkTS compilation, breakpoint delivery, state retention and visual
rendering are not verified. See `docs/harmony-toolchain.md` for the separate authorization blocker.

## Verified Android rendering boundary

`scripts/check_fixture_compilation.py` regenerates the fixture through the actual CLI, diffs it against the checked-in
`Expected.kt`, compiles it, and stages that exact source in the application test source set for its real resource
namespace. It also verifies shared settings resources against the app and stages only the fixture-specific navigation
string; duplicate resources are not accepted as evidence.

The Native JVM Compose tests use the real `WindowSizeClass.calculateFromSize` for platform classification and drive
native `WindowWidthSizeClass` parameter changes through the actual generated screen. They exercise typed input,
parent binding, compact→expanded resize, 2× font scale, native `NavHost` push and the same model instance. The
Robolectric test Activity does not dispatch a physical system-back button, so the test explicitly drives the native
`NavController.popBackStack()` and checks restored content; Android system-back dispatch is a separate device test.
compact, expanded and expanded-large-text PNGs are written to `app/build/reports/native-jvm-compose/` and published
with JUnit reports by CI.

**These are Native JVM Compose captures, not device or emulator screenshots.** They do not establish physical
foldable behavior, actual window-manager resizing, process restoration, IME/focus retention, visual parity across
platforms, screen-reader traversal, physical Android system-back dispatch or performance. No device or emulator was
started for this slice. At 2× text scale, the two-pane example can exceed the deliberately narrow Native JVM host;
its inspected capture records that clipping limit rather than claiming full large-text visual accessibility. A
production host must provide sufficient width or an already supported native scrolling/layout policy. Horizontal
`ScrollView` is outside this bounded slice, not silently approximated by the generator.
