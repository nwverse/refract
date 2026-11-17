# Interoperability with native code

Refract supports native code in both directions without a runtime adapter. Native component references and
platform-specific choices are declared in the Swift source; generated code contains only the selected, direct native
calls. The same source remains ordinary SwiftUI on iOS.

This document is the interop contract for the first vertical slice. It covers native components inside a generated
screen, explicit per-platform values and view subtrees, and generated screens called by native code. `docs/subset.md`
defines the general SwiftUI subset and `docs/mapping.md` defines the complete mapping file.

## Decisions

1. **Declarations live in Swift, platform implementations in the mapping.** A `RefractNativeView` is an ordinary
   SwiftUI view on iOS. Its stored properties form the source-level interface. Android and HarmonyOS each supply a
   native implementation through typed entries in `refract.json`.
2. **No erased view type.** `refractView` has independent generic parameters for its three branches. It returns the
   iOS branch directly on iOS; the generator selects one branch for each other platform. A modifier or animation can
   therefore differ without `AnyView`, a common wrapper view or runtime dispatch.
3. **Values are selected before generation.** `refractValue` is an ordinary generic Swift function returning its iOS
   argument. The generator checks that all alternatives have the same type and emits only the selected expression.
4. **Mapping entries are declarations, not code templates.** They contain symbols, imports, kinds and typed parameter
   names, not arbitrary target-language snippets. Their target signatures are checked by the platform compiler when
   the application builds.
5. **A generated screen is a reusable native component.** Compose emits a public `@Composable` function. ArkUI emits
   an exported `@ComponentV2` struct, not an application entry point. Neither requires a host container or global
   initialization.

## The iOS source prelude

The following declarations are the reference contract. A project normally places them in one separate Swift file
compiled only by its iOS target. They are source declarations, not a linked Refract library. The frontend's
`InteropFrontend` implements the equivalent declaration checks; iOS-only declarations need not be repeated in every
generated input file.

```swift
import SwiftUI

public protocol RefractNativeView: View {}

public struct RefractSpacing: Sendable {
    public let value: CGFloat

    public init(value: CGFloat) {
        self.value = value
    }

    public static let small = Self(value: 4)
    public static let medium = Self(value: 8)
}

public extension VStack {
    init(alignment: HorizontalAlignment = .center,
         spacing: RefractSpacing,
         @ViewBuilder content: () -> Content) {
        self.init(alignment: alignment, spacing: spacing.value, content: content)
    }
}

public extension HStack {
    init(alignment: VerticalAlignment = .center,
         spacing: RefractSpacing,
         @ViewBuilder content: () -> Content) {
        self.init(alignment: alignment, spacing: spacing.value, content: content)
    }
}

public enum RefractNativeModifier {
    case testTag(String)
    case contentDescription(String)
    case retainCallback(identity: String)
    case contentType(String)
}

public extension View {
    @inlinable
    @inline(__always)
    func refractNativeModifier(_ operations: RefractNativeModifier...) -> some View {
        self
    }

    @inlinable
    @inline(__always)
    func padding(horizontal: CGFloat, vertical: CGFloat) -> some View {
        padding(EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal))
    }
}

@inlinable
@inline(__always)
public func refractValue<Value>(
    ios: Value,
    android: Value,
    harmonyOS: Value
) -> Value {
    ios
}

@inlinable
@inline(__always)
@ViewBuilder
public func refractView<IOS: View, Android: View, HarmonyOS: View>(
    @ViewBuilder ios: () -> IOS,
    @ViewBuilder android: () -> Android,
    @ViewBuilder harmonyOS: () -> HarmonyOS
) -> IOS {
    ios()
}
```

The three `refractView` generic parameters are deliberately independent: different modifier chains can produce
different concrete Swift types. Swift type-checks all three branches even though only the iOS branch executes.
`RefractSpacing` makes the documented `.small`/`.medium` container spacing valid Swift: the standard stack
initializers accept `CGFloat?`, not these names. The overloads forward immediately to the native stack initializer
and do not create a wrapper view or a global spacing lookup. `refractNativeModifier` is a no-op on the iOS branch;
its typed operations are lowered only in the selected Android or HarmonyOS branch. The directional
`padding(horizontal:vertical:)` declaration is not a standard SwiftUI overload: the app-owned source extension maps
it to ordinary edge insets. These helpers are compile-time source declarations, not a linked runtime or a reason to
import Refract into an iOS target. The reserved helpers are not imported into generated targets; a project keeps the
reference declarations in its own iOS source. A conflicting local overload with the reserved names is a diagnostic,
not a way to change selection semantics.

The iOS example compiles uniquely named source-only inputs for the native-measurement, platform-value and
platform-view contracts, together with these declarations and the application-owned typography token. The repository
check requires those files to remain byte-identical to their canonical fixtures: unique basenames are necessary
because Xcode otherwise merges several `Input.swift` inputs into one `Input.stringsdata` output. This covers the real
`Binding(get:set:)` initializer, both typed platform-selection helpers, native measurement spellings and directional
padding with SwiftUI's semantic type checker. The canonical platform-value fixture uses
`Text(verbatim: refractValue(ios:android:harmonyOS:))` so the iOS-selected `String` flows through SwiftUI's
`Text(verbatim:)` initializer — matching the verbatim literal emitted by both native backends. Generator parsing
alone is not evidence that these constructs compile.

## Native components inside Refract

Declare a marker view with immutable stored properties and implement its `body` as ordinary SwiftUI. The body is the
iOS implementation and is not translated. Stored-property order is the argument order; there are no default values or
variadic parameters in this version.

```swift
struct RoutePreview: RefractNativeView {
    let zoom: Double
    let showsTraffic: Bool

    var body: some View {
        // This iOS implementation is not translated for other platforms.
        Text("Route preview")
    }
}

struct RouteScreen: View {
    var body: some View {
        RoutePreview(zoom: 12.0, showsTraffic: true)
    }
}
```

The mapping supplies the hand-written native symbols. The canonical `schemaVersion: 1` representation is defined in
`docs/mapping.md`: `android.nativeComponents` and `harmonyOS.nativeComponents` use the shared typed parameter and
argument-binding records. The compact `version: 1` form below is a compatibility representation accepted by the
same loader, not a second registry or a runtime format. Parameter arrays follow the Swift declaration order; `swift`
is the external Swift label, `name` is the target label or object-literal property, and `type` is the target type.

```json
{
  "version": 1,
  "nativeComponents": [
    {
      "swift": "RoutePreview",
      "android": {
        "kind": "composable",
        "symbol": "RoutePreview",
        "module": "example.maps",
        "parameters": [
          { "swift": "zoom", "name": "cameraZoom", "type": "Double" },
          { "swift": "showsTraffic", "name": "showsTraffic", "type": "Boolean" }
        ]
      },
      "harmonyOS": {
        "kind": "component",
        "symbol": "RoutePreview",
        "module": "example.maps",
        "parameters": [
          { "swift": "zoom", "name": "cameraZoom", "type": "number" },
          { "swift": "showsTraffic", "name": "showsTraffic", "type": "boolean" }
        ]
      }
    }
  ]
}
```

The relevant generated calls are:

```kotlin
import example.maps.RoutePreview

RoutePreview(cameraZoom = 12.0, showsTraffic = true)
```

```typescript
import { RoutePreview } from 'example.maps';

RoutePreview({ cameraZoom: 12.0, showsTraffic: true })
```

There is no registration call, reflection, string-based lookup or adapter. The application owns the imported
implementation. The mapping declares its target signature; the normal Kotlin or ArkTS compiler verifies that
signature against the actual implementation. Refract never claims to have validated a target API merely because a
JSON file parsed successfully.

### Source and mapping checks

For every native call, before either backend writes output, the frontend/lowering boundary checks:

- The called type conforms to `RefractNativeView` and is not a generated screen or an unsupported arbitrary SwiftUI
  type.
- Every call argument is labeled, in declaration order, and has the stored property's source type.
- The mapping has exactly one entry for the source type and an implementation for each requested target.
- Both target parameter arrays contain exactly the declared properties, in the same order, with valid target names
  and a type compatible with the source type.
- The symbol and module are explicit identifiers, not arbitrary code. Imports are deterministic and deduplicated.

The v0 value boundary is `String`, `Bool`, `Int` and `Double`, plus expressions supported by the state/model
contract. Native component declarations additionally accept `Image` and `LocalizedStringKey` for app-owned static
image resources and localized text, and the explicitly bounded `RemoteImageLoader` service protocol. `Image` arguments
must be literal `Image("lowercase_resource_name")` expressions; string keys must resolve in both resource catalogs.
A `RemoteImageLoader` must be injected as an explicitly typed screen input and cannot be constructed in the view.
These native-only parameter types are not model, state, binding or arbitrary object values. The bounded remote-image
lifecycle, URL policy and platform verification limits are specified in `docs/remote-images.md`.
Closures and arbitrary Swift objects are otherwise rejected until their typed native representation is specified;
they are never converted to untyped target expressions.

The accepted target-type mappings are:

| Swift | Kotlin | ArkTS |
| --- | --- | --- |
| `String` | `String` | `string` |
| `Bool` | `Boolean` | `boolean` |
| `Int` | `Int` | `number` |
| `Double` | `Double` | `number` |

`Int` values must be integral when emitted for ArkTS. The generator does not silently round, coerce or add a cast.

### Diagnostics

Diagnostics use the repository's stable diagnostic rendering. The construct name, expected signature and corrective
action appear in the message or suggestion.

| Code | Rejected construct | Alternative |
| --- | --- | --- |
| `RFNATIVE001` | Calling a view with no `RefractNativeView` declaration | Declare the marker view or use a supported built-in |
| `RFMAP002` | No target implementation entry for a declared native view | Add the target's typed mapping entry |
| `RFMAP003` | Missing, extra, reordered or mistyped mapping parameters | Match the stored-property signature exactly |
| `RFNATIVE002` | Wrong label, order, count or source argument type | Use the memberwise SwiftUI initializer signature |
| `RFNATIVE003` | A `refractValue` or `refractView` alternative is absent, repeated or differently typed | Supply the three required alternatives with compatible types |
| `RFNATIVE004` | Unknown/mistyped native measurement operation, invalid receiver or unstable callback capture | Use the closed `refractNativeModifier` operations and explicit stable model/item identity |
| `RFVIEW005` | A free-form `#if` in generated input | Use `refractValue`, `refractView` or a native component |
| `RFSEM001` | Side-effecting, opaque or otherwise unsupported branch content | Use a supported value, view subtree or declared model |

An error prevents both output files from being written. Refract never emits a comment, empty view, placeholder value
or iOS expression in place of a missing target implementation.

## Native animation, reduced motion and identity

A native transition uses the same `RefractNativeView` boundary, not a shared animation description. Keep the source
signature to the state needed by every implementation. The representative save confirmation in
`Fixtures/interop-native-animation/` declares only `visible: Bool` and `identity: String`: no duration, curve, target
code, arbitrary closure or animation object crosses the boundary.

The declaration's body remains ordinary SwiftUI. It reads `@Environment(\.accessibilityReduceMotion)` and chooses
`.identity` instead of `.opacity`; `.id(identity)` gives the content a stable identity. This environment property is
an iOS-only implementation input, not a native-component argument. Other property wrappers are still
`RFNATIVE001` diagnostics rather than an implicit expansion of the generated interface. The body is not translated.

On Android, the application-owned `NativeSaveConfirmation` in
`examples/android/app/src/main/java/com/example/refract/animation/` uses `AnimatedVisibility` and
`MutableTransitionState`. `key(identity)` replaces the remembered transition when identity changes; the native
composition disposes the old content. An exit removes its content only after the native transition finishes, and
leaving the composition disposes it immediately. The component reads `MotionDurationScale` from the recomposer's
coroutine context. At zero it uses `EnterTransition.None` and `ExitTransition.None`; otherwise it uses native fades.
It does not run a parallel timer or translate a duration from another platform.

On HarmonyOS, the mapping delegates to the application's typed `NativeSaveConfirmation` component. The implementation
owns its equivalent native visibility transition, stable-key replacement, disposal and accessibility preference. It
must not reuse the component's remembered state after an identity change, and reduced motion must produce the same
final visibility without an animated transition. The golden ArkTS is a direct call with typed arguments, not a native
implementation. No HarmonyOS compiler or runtime was available to verify this implementation contract.

The optional Android observer is app-owned and supplied through a `CompositionLocal`; it is absent from both generated
entry points. Its only purpose in the example is to let tests observe actual transition idle/running state and disposal.
The test host injects the observer around the unmodified CLI-generated `SaveConfirmationScreen`; it does not add a
test parameter by rewriting generated code.

Run the Android behavior checks with `:fixtures:testDebugUnitTest` after staging the fixtures. The tests execute real
Compose on Robolectric: an ordinary transition runs and settles, identity replacement disposes the old content during
the transition, exit removes content, zero duration scale skips enter/exit motion, and leaving composition disposes
content. They do not exercise a device, emulator, physical animation-duration setting or performance benchmark.
SwiftUI behavior also requires an Apple toolchain; generator tests do not establish that evidence.

## Per-platform values, modifiers and animations

Use `refractValue` for scalar values and tokens whose source types agree:

```swift
Text("Status")
    .padding(refractValue(ios: 4, android: 12, harmonyOS: 12))
```

Compose receives `.padding(12.dp)` and ArkUI receives `.padding(12)`; no iOS branch appears in either output.

For per-platform **literal text**, use `Text(verbatim: refractValue(ios:android:harmonyOS:))` with a string
literal in every branch:

```swift
Text(verbatim: refractValue(ios: "iOS", android: "Android", harmonyOS: "HarmonyOS"))
```

The generated Android call is `Text(text = "Android")` and the ArkUI call is `Text('HarmonyOS')`. On iOS the
ordinary `refractValue<Value>` helper returns its `String` argument, which feeds SwiftUI's `Text(verbatim:)`
initializer — the same verbatim, non-localized semantics as the two native backends. No runtime adapter or
text-selection layer is involved.

The unlabeled localized form `Text(refractValue(ios:android:harmonyOS:))` is **not** accepted: on iOS it would
select SwiftUI's `Text(_: LocalizedStringKey)` initializer and reinterpret the iOS branch as a localization key,
while the native backends already emit their branch as a verbatim literal. That source produces a build-time
`R.string.unsupported_expression` diagnostic, names the divergence and points to the `Text(verbatim:)` form. A
per-platform **localized** string is not a supported v0 contract; if a project genuinely needs different localized
text per platform, use a single canonical key resolved through each platform's ordinary resource catalogs (see
`docs/localization.md`).

Use `refractView` when a view, modifier chain or animation differs. Each branch is a supported view subtree for the
selected backend, while the iOS branch can use the ordinary SwiftUI subset accepted by that source file:

```swift
refractView(
    ios: {
        Text("Status").padding(refractValue(ios: 4, android: 12, harmonyOS: 12))
    },
    android: {
        Text("Status").padding(refractValue(ios: 4, android: 12, harmonyOS: 12))
    },
    harmonyOS: {
        Text("Status").padding(refractValue(ios: 4, android: 12, harmonyOS: 12))
    }
)
```

Only `Text(text: "Status").padding(12.dp)` is generated in the Android subtree and only
`Text("Status").padding(12)` in the ArkUI subtree. No extra container or wrapper is introduced. A more complex
modifier or animation follows the same rule; arbitrary unsupported target code inside a closure is still a
compile-time diagnostic.

Branch expressions must not perform side effects. Model reads and values already supported by the typed expression IR
are allowed; business logic belongs behind a model. This keeps the iOS helper's unused arguments benign and makes
selection deterministic.

### Why not a modifier taking three `AnyView` values?

That alternative forces type erasure on iOS and can change SwiftUI's view identity. A single generic `Content` for all
closures instead requires unrelated modifier chains to have the same concrete type. Independent generic parameters
avoid both problems. Although the source syntax wraps a subtree, generation flattens the selection to that subtree.

Free-form conditional compilation is not an alternative. It can hide arbitrary declarations from the generator and
let platforms drift, so the frontend rejects it even when it names a supported operating system.

## Measurement and retained native callbacks

A benchmark or an existing native test harness can require native measurement hooks without changing the source's
accessibility or callback semantics. Use an explicit platform view branch and the closed
`refractNativeModifier` operation list; do not invent SwiftUI `testTag` or `remember` modifiers for iOS:

```swift
refractView(
    ios: {
        Toggle("settings.item\(row.id)", isOn: itemEnabled)
            .accessibilityLabel(row.title)
    },
    android: {
        Toggle("settings.item\(row.id)", isOn: itemEnabled)
            .refractNativeModifier(
                .testTag("settings_toggle"),
                .contentDescription(row.title),
                .retainCallback(identity: "settings.setEnabled")
            )
    },
    harmonyOS: {
        Toggle("settings.item\(row.id)", isOn: itemEnabled)
            .refractNativeModifier(
                .testTag("settings_toggle"),
                .contentDescription(row.title)
            )
    }
)
```

`RefractNativeModifier` is a source-owned, closed operation enum. It is not a runtime modifier object, an arbitrary
Kotlin/ArkTS string or a general modifier language. The initial accepted operations are:

- `testTag(String)`: Compose `Modifier.testTag` and ArkUI `.id`, on the actual selected control;
- `contentDescription(String)`: Compose `Modifier.semantics { contentDescription = ... }` and ArkUI
  `.accessibilityText`, not a fabricated SwiftUI modifier;
- `retainCallback(identity: String)`: on Android, retain a checked model action with all of its captured stable
  references. A no-argument action remembers its model; a typed item-toggle action remembers `(model, row.id)`.
  The identity must be a literal ASCII dot-separated name of the source action. HarmonyOS rejects this operation
  until a native typed callback-identity contract is available; it is never silently discarded;
- `contentType(String)`: a lowercase ASCII row-shape identifier, applied exactly once to a generated child View
  that is the direct content of `List(model.items)` or `List { ForEach(model.items) }`. Compose emits
  `contentType = { "setting" }` and ArkUI attaches `.reuse({ reuseId: () => 'setting' })` to that same child call.
  A page-level child, nested row, Toggle, arbitrary operation list, computed identity or duplicate declaration is
  `RFNATIVE004`; it never falls back to callback retention. ArkUI reuse requires API 18 or newer and the matching
  reusable-component contract. The generator fixture records this source shape, but no HarmonyOS native compiler is
  available here, so it is not toolchain or runtime verification.

Only values whose source type is statically known to be `String` are accepted for measurement/accessibility text.
String interpolation may combine literal segments with typed scalar item/model values, for example
`"setting_row_\(row.id)"`; Compose emits native Kotlin interpolation and ArkUI emits an ArkTS template literal.
Unknown, untyped or non-scalar expressions remain `RFNATIVE004` build-time errors, not arbitrary string conversions.
A list item uses the same typed item-property resolution as other supported expressions. The callback's model and
current item identity are part of the `remember` key: a literal identity alone cannot retain a callback that captures
an old model or a different row. Arbitrary captures, computed identities, unknown operations and duplicate operations
are `RFNATIVE004` build-time errors.

The source remains ordinary SwiftUI on iOS. Its real `.accessibilityLabel` behavior is accepted only in the explicit
iOS branch; an iOS branch does not supply Android test identifiers. There is no generated registry, callback cache,
wrapper view or runtime platform branch. Typography continues through declared design tokens, such as
`MaterialTheme.typography.bodyLarge`; row modifiers use ordinary native chains, including
`.padding(horizontal: 16, vertical: 8)` with one direct Compose `padding` call and the corresponding ArkUI edge object.

`Fixtures/interop-native-measurement` exercises these forms through the real CLI on both backends, including the
typed item toggle from the model-action contract. It is included in the real Android fixture compilation manifest.
That proves accepted Kotlin compilation, not macrobenchmark parity or device performance. `bench/android` generates
its real screen through the CLI and preserves the unchanged hand-written reference; macro execution and complete
paired timing evidence belong to #120.

## Refract inside native code

Given `struct RouteScreen: View` with an empty input signature, generation produces these public entry points:

```kotlin
@Composable
public fun RouteScreen(modifier: Modifier = Modifier) {
    // Direct native view calls.
}
```

```typescript
@ComponentV2
export struct RouteScreen {
  build() {
    // Direct native view calls.
  }
}
```

A hand-written Compose caller uses the generated function normally:

```kotlin
import refract.generated.RouteScreen

@Composable
fun NativeHostScreen() {
    RouteScreen()
}
```

A hand-written ArkUI parent imports and places the generated component in its `build` method:

```typescript
import { RouteScreen } from './RouteScreen';

@ComponentV2
export struct NativeHostScreen {
  build() {
    RouteScreen()
  }
}
```

Neither caller supplies a Refract context, registry, lifecycle owner or engine. The generated file's header identifies
its source; regeneration replaces it as a whole. Native code imports the public entry point but does not edit it.

### Public signature rules

- The Swift type name is the Kotlin function name and the ArkUI struct name, unchanged after identifier validation.
- Swift stored input properties become ordered Kotlin parameters. Their types and defaults are explicit; callers use
  named Kotlin arguments.
- Every generated Compose entry point has a trailing `modifier: Modifier = Modifier` root-extension parameter, even
  when the Swift input has no stored inputs. It is applied before the source-owned root modifiers, matching the
  native call-site convention. This is a platform-specific native call-site extension point, not a runtime adapter
  or an added view container.
- ArkUI inputs use the observation rules in `docs/performance.md` and the model contract. Required inputs are marked
  with the appropriate V2 parameter decorator and passed in the component's object literal.
- `@Binding` and model properties become the typed state/interface parameters defined by the state workstream, never
  untyped dictionaries or runtime-resolved services.
- Generated components have no `@Entry`; only the hand-written application chooses an entry component.
- Input files declaring more than one screen produce one public entry point per screen in source order. Helper and
  native marker declarations do not create public generated screens.

A signature-affecting change is visible in the golden Kotlin and ArkTS files. The `interop-native-callers` fixture also
contains hand-written callers for both platforms. Platform example builds are the eventual compile check for these
imports and calls; text goldens alone do not claim toolchain validation.

## Typed navigation hosts

`docs/navigation.md` defines the bounded `NavigationStack(path:)` contract. Generated root screens accept a typed
navigation callback; a separate destination component calls same-file typed model screens or zero-argument
`RefractNativeView` implementations. The native host owns `NavController`, `NavPathStack`, back and lifecycle, so no
second navigation stack, runtime registry or untyped destination object is generated. Android generated output and
its real native host compile together; iOS/ArkTS compilation and device lifecycle remain explicitly unverified here.

## Verification and trade-offs

Golden fixtures cover a native call, native callers of a generated component, scalar selection, view/modifier
selection, missing and mismatched native declarations, and rejected conditional compilation. Backend unit tests cover
identifier and signature validation separately from source parsing. Regenerating every fixture must produce a
byte-identical result.

This first version deliberately excludes arbitrary closures, overloaded native initializers, runtime component
registration, automatic target-code parsing and arbitrary target source templates. Those would either weaken type
checking or require a runtime bridge. Native implementations remain application-owned and are checked by their normal
compiler. The approach adds no generated abstraction, start-up work or Refract binary dependency; device benchmark
claims belong to the benchmark workstream, not to these source-level tests.
