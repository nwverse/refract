# State, bindings and model observation

This is the state contract for the first vertical slice. It keeps ownership in the Swift source, makes observation a
typed platform boundary, and emits only platform SDK constructs. It does not add a Refract runtime, a view-model base
class, a global store or a subscription adapter.

## Decisions

- **HarmonyOS uses state management V2 and requires API 12 or later.** `@ComponentV2`, `@Local`, `@Param`, `@Event`,
  `@ObservedV2` and `@Trace` all start at API 12. The V1 alternatives copy values (`@Prop`) or impose different
  reference and decorator requirements (`@Link`/`@ObjectLink`); they do not preserve the same source contract.
- **Compose model properties expose `State<T>`.** `State` is an interface with a `value` property; it is not a
  Refract wrapper. The model implementation owns its mutable backing storage and its lifecycle. A generated screen
  never casts a model, subscribes imperatively, collects a flow in the UI, or creates a mirror of model state.
- **ArkUI model interfaces are plain typed property and action contracts.** Their required implementation contract
  is an `@ObservedV2` class whose observable properties are `@Trace`. Decorators cannot be requirements of an ArkTS
  interface, so the compiler cannot prove this through the interface alone. An example implementation and the
  integration build are mandatory evidence; an undecorated implementation must not be presented as supported.
- **`@Binding` is a two-way value/callback contract, not shared mutable storage.** Compose receives a value and a
  setter callback. ArkUI receives `@Require @Param` and an `@Event` callback. The child never assigns its `@Param`
  directly. The generator always supplies the paired callback; the SDK-required empty default only satisfies ArkTS
  definite initialization and is not used as a missing-binding fallback. `@Require` does not decorate `@Event`.
- **Read observable values where the emitted UI uses them.** Do not snapshot model properties into local value
  variables at the top of a component. An event-handler read is not a composition read and must not be treated as
  one by the frontend.
- **First-slice types are `String`, `Bool`, `Int`, `Double` and arrays of supported primitive values.** Optional
  values, nested objects, reference mutation, collection mutation through bindings, computed model properties and
  asynchronous streams are rejected until their semantics and observation are specified. The app keeps that logic
  behind a supported model interface.

The official ArkUI contracts are recorded in the OpenHarmony documentation for
[`@Local`](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/state-management/arkts-new-local.md),
[`@Param`](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/state-management/arkts-new-param.md),
[`@Event`](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/state-management/arkts-new-event.md),
and
[`@ObservedV2`/`@Trace`](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/state-management/arkts-new-observedV2-and-trace.md).
The Compose behavior follows the [state and Jetpack Compose documentation](https://developer.android.com/develop/ui/compose/state).

## Swift ownership forms

```swift
struct CounterRow: View {
    @State private var count: Int = 0

    var body: some View {
        Button("Increment") { count += 1 }
    }
}

struct EnabledRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle("Enabled", isOn: $isEnabled)
    }
}

protocol ExtensionSettingsModel: RefractModel {
    var title: String { get }
    var isEnabled: Bool { get }
    func setEnabled(_ value: Bool)
}

struct ExtensionSettings: View {
    let model: ExtensionSettingsModel

    var body: some View {
        VStack {
            Text(model.title)
            Button("Disable") {
                model.setEnabled(false)
            }
        }
    }
}
```

`@State` is private component-owned storage with a local, type-correct initializer. `@Binding` has no independent
initial value: its parent supplies both the current value and the write path. A plain `let` whose type is a declared
`RefractModel` protocol is an external model input. The consuming iOS source declares the empty `RefractModel` marker
protocol (or later adopts a compile-time-only support declaration); the generated native sources do not import a
runtime library. A `var` model property or a model property wrapper is not accepted as another ownership mechanism.

`$property` is accepted only for a binding passed to a supported control or child component. Arbitrary projected
values, key-path expressions, `wrappedValue` and `projectedValue` are rejected. A button action may call a supported
model method or assign a supported state/binding value, including `+=` for numeric local state. Broader Swift
statement translation and arbitrary custom bindings are rejected. Two closed custom-binding forms preserve an ordinary
SwiftUI write path without making a get-only model property writable. The first is a Bool `Toggle`
inside a typed `Identifiable` list row. Its getter must read a stored Bool property of that exact row, and its setter
must invoke one declared model action with that row's stored `String`/`Int` id and the new Bool value:

```swift
Toggle("settings.item\(row.id)", isOn: Binding(
    get: { row.enabled },
    set: { value in model.setEnabled(row.id, value: value) }
))
```

The model declares `func setEnabled(_ id: Int, value: Bool)` (with the matching identity type). Compose emits a
`Switch` reading `row.enabled` and calling `model.setEnabled(row.id, enabled)`. ArkUI emits the same direct model call
from its `Toggle.onChange` with the scope-safe `enabled` parameter, even when the row itself is named `value`. The app
supplies `@ObservedV2`/`@Trace` row values and its `BasicDataSource` as specified below. The title must have at least
one typed interpolation argument, and every argument must be a declared scalar property of that same row; static or
model-only titles do not establish this item association. An interpolated item title uses native string formatting,
not string substitution. Different rows, non-Bool values,
mismatched labels/types/identities, side effects and general getter/setter computation are build-time errors. No
observer registry, per-row binding adapter or synthetic model mutation is generated. See
`Fixtures/v0-item-toggle/` for the exact native shape.

The second is a String `TextField` whose getter reads one declared model String property and whose setter calls the
corresponding `set<Property>` action with one String parameter on that same model. `$model.searchText` is not accepted:
the get-only protocol does not supply a SwiftUI writable projection. Use the valid explicit binding instead:

```swift
TextField("search.results.placeholder", text: Binding(
    get: { model.searchText },
    set: { value in model.setSearchText(value) }
))
```

Compose reads `model.searchText.value` and calls `model.setSearchText(value)` from `onValueChange`; ArkUI reads
`this.model.searchText` and calls the same action from `onChange`. Getter/setter owner, type, label or side-effect
mismatches are `state.invalid_projection` errors. The app owns debouncing, cancellation and request generations;
there is no generated subscriber, writable-model fallback or paging adapter.

## Bounded incremental search pages

`Fixtures/list-paged-search/` adds loading, error, empty and result branches around the same keyed lazy-list lowering.
Loading and error indicators do not remove an existing list from the native composition; empty is a settled result,
not a transient loading state. Its model actions are `setSearchText`, `loadNextPage` and `retry`; transport execution,
cancellation and page merging remain native application code on every platform. A useful bounded implementation has
one in-flight page, assigns a new generation and cancels the old request when the query changes, and accepts a
completion only when its generation, query and page match that active request. A duplicate completion or a skipped page is ignored rather than merged.
Page zero replaces the snapshot; later pages append. Reusing an item id updates that logical row without creating a
second native key. Failure keeps accepted rows and retry requests only the failed next page. These rules keep native
keys stable, but do not imply transport retry, process persistence or a measured scrolling/performance result.

The Android example's hand-written `IncrementalSearchResultsModel` implements this boundary and its JVM tests use an
in-memory scripted transport: no network request or device behavior is part of the evidence. Its ArkUI counterpart
must similarly update an app-owned `BasicDataSource` and issue the appropriate insert/reload notifications; the
ArkTS golden is source-only until the authorized HarmonyOS compiler and runtime are available. Native request
callbacks must arrive serially on the platform UI owner after the request-start call returns, and the owner must
cancel outstanding work when the model closes. No generated lifecycle or runtime registry supplies that ownership.
Generation counters are an internal implementation detail (zero-based in the example), not an API exposed to the
transport. Their equality, not a particular starting number, defines stale-response rejection.

## Compose output

```kotlin
@Composable
public fun CounterRow(modifier: Modifier = Modifier) {
    var count by remember { mutableStateOf(0) }
    Button(onClick = { count += 1 }) {
        Text("Increment")
    }
}

@Composable
public fun EnabledRow(
    isEnabled: Boolean,
    onIsEnabledChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    Switch(checked = isEnabled, onCheckedChange = onIsEnabledChange)
}

public interface ExtensionSettingsModel {
    public val title: State<String>
    public val isEnabled: State<Boolean>
    public fun setEnabled(value: Boolean)
}

@Composable
public fun ExtensionSettings(model: ExtensionSettingsModel, modifier: Modifier = Modifier) {
    Button(onClick = { model.setEnabled(false) }) {
        Text("Disable")
    }
    Text(model.title.value)
}
```

The concrete control names are illustrative here; the shared Compose backend owns the final view signatures. State
lowering owns the observable property access, not a second implementation of view generation.

A local `@State` declaration produces `var property by remember { mutableStateOf(initialValue) }`; delegated reads
and writes retain the same native snapshot observation. Model property reads append `.value` at the leaf. Binding reads
use the value parameter directly and binding writes call its
setter callback. A state passed into a child binding uses `childState.value` and `{ value -> childState.value = value
}`. A model-to-child binding is allowed only when the model declares the matching setter action; it cannot synthesize
a write to a get-only property.

`State<T>` makes observation explicit in the Kotlin interface. Compose snapshot reads register with the native
snapshot system and invalidate scopes that read the changed value; no runtime registry is emitted. `remember` retains
only component-local state. Model creation, activity retention, process restoration and external update delivery are
owned by the app, not the generated component.

Compose stability annotations are not added to an interface merely to silence a compiler report. The backend must
not claim skippability without the stability analysis or a project-approved stability contract from #9. Fine-grained
observation and composable skipping are separate concerns.

## ArkUI output

```typescript
export interface ExtensionSettingsModel {
  title: string;
  isEnabled: boolean;
  setEnabled(value: boolean): void;
}

@ComponentV2
export struct CounterRow {
  @Local private count: number = 0;

  build() {
    Button('Increment')
      .onClick(() => {
        this.count += 1;
      })
  }
}

@ComponentV2
export struct EnabledRow {
  @Require @Param isEnabled: boolean;
  @Event onIsEnabledChange: (value: boolean) => void = (value: boolean): void => {};

  build() {
    Row() {
      Text($r('app.string.settings_enabled'))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: this.isEnabled })
        .onChange((value: boolean) => {
          this.onIsEnabledChange(value);
        })
    }
    .justifyContent(FlexAlign.SpaceBetween)
  }
}

@ComponentV2
export struct ExtensionSettings {
  @Require @Param model: ExtensionSettingsModel;

  build() {
    // Reads remain this.model.title and this.model.isEnabled at the leaf.
    // A button action invokes this.model.setEnabled(false).
  }
}
```

A hand-written implementation follows this contract:

```typescript
@ObservedV2
export class SettingsModel implements ExtensionSettingsModel {
  @Trace title: string;
  @Trace isEnabled: boolean;

  constructor(title: string, isEnabled: boolean) {
    this.title = title;
    this.isEnabled = isEnabled;
  }

  setEnabled(value: boolean): void {
    this.isEnabled = value;
  }
}
```

The implementation belongs to the consuming app; this class is not emitted into every generated screen. `@Trace`
changes notify the UI associated with that property, whereas an undecorated property is not observable. A `@Param`
observes replacement of its model reference but does not by itself make class member changes observable. `@Local`
similarly observes assignment of the decorated value, with deep class-property observation supplied by
`@ObservedV2`/`@Trace`.

### Identified-list replacement

For a source property such as `var items: [SettingItem] { get }`, the generated ArkUI interface requires
`items: BasicDataSource<SettingItem>`; Compose retains `State<List<SettingItem>>`. These are two native boundaries
for the same declared source collection, not a requirement that the app's shared model use an ArkUI type.

The HarmonyOS app owns a `BasicDataSource` implementation and its storage. When its Swift-facing model receives a
replacement array, that implementation updates its storage and delivers the corresponding native data-source change
notifications (for example reload, or explicit insert/delete/move operations). `LazyForEach` subscribes through
`registerDataChangeListener`; generated code does not copy the array, poll it, watch it with `@Monitor`, or invent a
second observer registry. Stable `String`/`Int` ids are converted to string keys so those updates preserve logical
row identity. In-place collection mutation is outside the source subset and must not be presented as an observable
replacement.

The source's value-type item becomes an explicitly typed native class for ArkUI. Scalar item fields are immutable in
the first list slice. Mutable fields require the app-facing observation implementation to supply native V2 property
observation; the generated class shape alone is not evidence of compiler acceptance or update behavior.

The following app-owned pseudocode illustrates the boundary; it is not emitted by Refract and has not been compiled
with a HarmonyOS SDK here. `AppItemDataSource` is the application's concrete `BasicDataSource<SettingItem>` subclass.

```typescript
@ObservedV2
export class SettingsListModelImplementation implements SettingsListModel {
  @Trace items: BasicDataSource<SettingItem>;

  constructor(items: BasicDataSource<SettingItem>) {
    this.items = items;
  }

  replaceItems(replacement: Array<SettingItem>): void {
    let source = this.items as AppItemDataSource;
    source.replaceAll(replacement);
    source.notifyReload();
  }
}
```

`replaceAll` and `notifyReload` are illustrative application implementation methods on that concrete subclass, not
claimed `BasicDataSource` SDK methods without compiler verification. A whole-data reload is the conservative
replacement path; fine-grained notifications may be used when the app can describe the exact change. No device
performance claim follows from this structural contract.

After `@Event` invokes the parent write, synchronization back to the child `@Param` is asynchronous. Generated event
handlers must not read the child parameter and assume that it has already changed. Controls that require this
immediate value behavior must receive an explicit backend mapping or be rejected, rather than assigning `@Param` as a
workaround.

For a parent local state passed to a child binding, the parent supplies the value and an arrow callback assigning the
new value to its `@Local`. For a parent binding passed through, it forwards both its value and callback without
creating intermediate state.

## Diagnostics

Diagnostics use the shared source-location and stable-code format. The owning construct is named, the observation or
ownership reason is explained, and a supported alternative is suggested.

| Code | Rejected construct | Alternative |
| --- | --- | --- |
| `state.invalid_declaration` | `@ObservedObject`, `@StateObject`, `@EnvironmentObject`, `@Environment`, `@AppStorage`, `@SceneStorage`, `@FocusState`, `@GestureState` | local `@State`, parent `@Binding`, or a declared model interface |
| `state.invalid_declaration` | unsupported wrappers, malformed declarations, or a missing local initializer | use a supported wrapper and literal initialization |
| `state.binding_initializer` | `@Binding` with an initial value | pass the parent's value and callback instead |
| `state.invalid_projection` | unsupported `$` projection or `wrappedValue`/`projectedValue` access | use a supported binding input or child argument |
| `state.unsupported_type` | unsupported optional, nested object or collection mutation | expose supported values and actions on a model |
| `model.invalid_inheritance` | inheritance beyond the single `RefractModel` marker | keep the protocol flat |
| `model.invalid_property` | writable, computed, static, untyped or initialized model requirement | a get-only typed instance property |
| `model.invalid_action` | async, throwing, generic, variadic, static or unsupported-return action | a synchronous, nonthrowing, `Void` action with supported parameters |
| `model.unsupported_requirement` | associated types, initializers, subscripts or arbitrary protocol members | keep them in native code outside the model boundary |
| `model.duplicate_member` | duplicate properties/actions after Swift argument-label resolution | give each requirement a unique native signature |
| `model.unsupported_binding` | `$model.property` without a declared matching setter | add the explicit model action or pass a parent binding |

A diagnostic stops output for the affected source. No undecorated model fallback, silently mutable interface property,
fake callback default or opaque `any`/`Any` value is emitted.

## Performance argument and evidence

The generated access paths are the same primitives a hand-written native component uses: Compose `State` reads,
ArkUI V2 decorators and direct callbacks. There is no copied model, generated observer list, runtime proxy, diffing
step or reflection. Property reads remain in the UI expression so the native toolkit can associate updates with the
consumer of that property. The model implementation owns storage updates, avoiding a generated second source of
truth.

This is a structural argument, not a measured no-regression result. The golden fixtures establish the generated
patterns. The performance workstream (#9) must compare a generated and equivalent hand-written stateful screen for
recomposition/re-render counts and frame times in release builds, on named devices. Simulator or emulator results
must be labelled and cannot close that measurement gap. A measured regression beyond the harness's noise threshold
blocks the generated pattern.

The first integration example must also compile a hand-written model implementation and exercise both a parent
binding and a model action. Without the HarmonyOS toolchain, golden ArkTS and source review can verify text but not
compiler acceptance or runtime observation; that limitation must remain explicit in the PR.
