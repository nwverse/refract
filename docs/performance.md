# Performance rules for generated code

This is the contract the Compose and ArkUI backends implement. Goal 2 is absolute: generated code must not perform
worse than the equivalent well-written native code it replaces. A rule's presence in this document is not itself a
measurement. Golden fixtures prove shape; compiler reports and compiled examples prove accepted native constructs;
paired release benchmarks measure the result.

## Evidence and ownership

- Each normative rule has a hand-written expected pattern in `Fixtures/performance/`. The shared generator and
  backends must make those cases pass as they implement the corresponding subset; placeholders do not count as
  generated-code coverage.
- `bench/android/` compiles the actual CLI-generated Compose settings screen next to its unchanged hand-written
  reference. The generated `GeneratedSettingRow` remains directly callable by the microbenchmark; there is no
  labelled stand-in or hand-edited generated Kotlin. Structural equivalence and compilation are not measurements.
- No benchmark-only optimization is added to a generated screen. Both variants use the same models, data, theme,
  controls, accessibility nodes and native lifecycle. Test tags are instrumentation, not a runtime view abstraction.
- A measured regression beyond the documented noise gate blocks the generated pattern. Baselines are not raised to
  hide a regression. More data can resolve noise; a favorable rerun cannot erase a reproducible regression.
- [Android](https://developer.android.com/topic/performance/benchmarking/benchmarking-in-ci) and
  [ArkUI](https://gitee.com/openharmony/docs/blob/master/en/application-dev/performance/readme-EN.md) metrics are
  platform-specific. Absolute numbers are never compared across devices, build modes, OS images or toolchain versions.

The current fixture and harness patterns use the merged `docs/state-and-models.md` contract: ordinary SwiftUI source
with `let model` and a `RefractModel` protocol; Compose `State<T>` at the typed model boundary; ArkUI V2 on API 12+.
There is no Refract base class, observer registry, proxy, interpreter, view-tree renderer or generated initialization.

## Native modal state

Sheets and alerts use the platform's own modal host. Compose conditionally calls Material 3 `ModalBottomSheet` or
`AlertDialog` while its typed Boolean is true and scopes alert-host notification to a `LaunchedEffect` in that same
branch; no controller registry, overlay layout, polling or start-up work is introduced. ArkUI uses the root's native
`.bindSheet` builder and observes only the alert's Boolean with `@Monitor`/`aboutToAppear` to notify the application's
native UIContext host. Do not call imperative dialog APIs from `build()` or mirror modal state in a generated cache.
Dismissal writes the original binding, so a second overlay model is never needed. `Fixtures/modal-sheet-state` and
`Fixtures/modal-native-host` show these patterns and retain ordinary root modifiers. Their golden/native-JVM checks
are structural and behavioral evidence, not frame-time or memory measurements; no modal performance claim is made
without a same-device generated-vs-native benchmark.

## Jetpack Compose

### C1: pass stable scalar inputs and keep the row's identity

Lower immutable row values to a generated row function with only the scalar inputs it reads. Compose can then skip
that function when an equal invocation occurs. Do not read an entire model inside every row or put `@Stable` on a
model merely to silence a compiler report. A data type's stability is established from the supported IR types and
project declarations; use the Compose compiler report as evidence.

`State<T>` is read at the consuming leaf, not copied into a screen-level local. A model interface is not declared
immutable just because its properties have getters: `State<T>` supports observation and mutable backing storage.
Prefer the model's typed properties and actions to a generated adapter, `remember { derivedStateOf { ... } }` mirror,
or `collectAsState` subscription unless the subset has explicitly defined that asynchronous source.

```kotlin
// Accepted: the model is used only by the action; row content stays narrow.
@Composable
private fun GeneratedSettingRow(model: SettingsModel, row: SettingRow) {
    Text(row.title)
    Switch(checked = row.enabled, onCheckedChange = { model.setEnabled(row.id, it) })
}
```

If a benchmark or compiler report shows that `row` causes avoidable recomposition, lower to its scalar properties
rather than adding a runtime equality or diffing layer. Do not infer stability of arbitrary application classes.
Unsupported reference mutation is rejected per the state contract.

**Fixture:** `Fixtures/performance/compose-state/Expected.kt`.
**Measurement:** compiler stability report; row recomposition count; frame p50/p99.

### C2: use stable `LazyColumn` keys and homogeneous `contentType`

Every lazy item has a key derived from the source's `Identifiable` identity, not an array index or object dump.
The key is stable, unique in the list and `Bundle`-saveable. All rows with the same emitted structure use the same
literal `contentType`; structurally different supported branches have an explicit finite type discriminator. A generated
child row can declare its stable row-shape name directly with `.refractNativeModifier(.contentType("setting"))` in either
canonical dynamic List form. `Fixtures/child-view-layout-priority` and `Fixtures/child-view-foreach-content-type` cover
that reviewed source-to-native contract.

```kotlin
items(
    items = model.rows.value,
    key = { row -> row.id },
    contentType = { "setting" },
) { row -> /* ... */ }
```

`LazyColumn`/`LazyRow`/`items` are emitted directly. Never render a long list through eager `Column` plus
`forEach`, wrap a lazy list in a second scroller, or add a generated paging/cache layer.

**Fixture:** `Fixtures/performance/compose-lazy-list/Expected.kt`.
**Measurement:** scroll frame p50/p99, startup, retained memory, visible-item count.

### C3: `remember` is for retained identity or expensive calculation

Keep local state and identities that must survive recomposition in `remember`, with complete keys. An action
capturing `model` and `row.id` may use `remember(model, row.id)`. If the reference uses an ordinary composable-lambda
parameter and the compiler already handles its allocation, unconditional caching can add cost instead of removing
it: compare before making it mandatory.

Do not repeatedly compute a genuinely expensive derived value in composition. First pass the derived value through
the app model. Only a supported, cheap, state-derived expression may use `derivedStateOf`, and its input reads stay
inside the calculation. Do not wrap every property or allocate lists/maps on every recomposition.

```kotlin
val onCheckedChange = remember(model, row.id) {
    { enabled: Boolean -> model.setEnabled(row.id, enabled) }
}
```

**Fixture:** `Fixtures/performance/compose-state/Expected.kt`.
**Measurement:** recomposition count, allocations, row microbenchmark and frame p50/p99.

### C4: defer state and scroll-position reads to their smallest consumer

Read `State.value` in the emitted UI expression or a small child, not in the screen's top-level local snapshot.
Keep callbacks direct: a callback reads a value at event time and does not thereby subscribe the whole composition.
A scroll listener or animation-derived value must not eagerly invalidate the parent; use native lambda-based reads
when the supported subset defines that behavior. No polling or synchronization adapter is emitted.

```kotlin
Text(model.title.value)
// Not: val title = model.title.value at the root of a screen that also owns the list.
```

**Fixture:** `Fixtures/performance/compose-state/Expected.kt`.
**Measurement:** root/row recomposition counts and local-state-update frame p50/p99.

### C5: native modifiers and ordinary functions, with no runtime help

Map supported modifiers directly, retain their source order, and avoid unconditional extra `Column`/`Row` wrappers.
A generated component is an ordinary `@Composable` with an explicit signature; no reflection, generic modifier map,
navigation host or runtime theme lookup is emitted. Generated and reference builds have the same shrinking,
compilation mode and baseline-profile policy. **Do not let ART inline both variants together and then report that
this proves equivalent performance.** Inspect both compiled functions, use frame-level measurements, and add a
realistic generated component body when the harness needs more work than a trivial header.

## ArkUI

### A1: V2 observation stays at property granularity

Generated components consistently use `@ComponentV2`, `@Local` for local state, `@Require @Param` for inputs and
`@Event` for parent writes. App model implementations use `@ObservedV2` with `@Trace` on each property the UI reads.
Interface declarations remain typed and unadorned; an implementation without the decorators is unsupported rather
than silently accepted. API 12 or newer is required.

`@Trace` invalidates only components associated with the changed property. Leave `this.model.property` at the
consuming leaf. A `@Param` model reference observes replacement but does not make its members observable. Do not
clone the model, add a generated observer list, use `@Monitor` for every member, or rebuild the whole screen on a
leaf change. The ownership details and event synchronization contract live in `docs/state-and-models.md`.

**Fixture:** `Fixtures/performance/arkui-observation/Expected.ets`.
**Reference:** [official `@ObservedV2`/`@Trace` contract](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/state-management/arkts-new-observedV2-and-trace.md).
**Measurement:** targeted re-render count and state-update frame p50/p99 on a compiled example.

### A2: `LazyForEach` uses a typed `IDataSource` and stable keys

A Swift `List`/`ForEach` with identity lowers to `List` + `ListItem` + `LazyForEach`. The application model supplies
an ArkUI-compatible `IDataSource` (a `BasicDataSource<Item>` in the v0 fixture) with a concrete item type; generated
code consumes it directly. Compose exposes the corresponding collection as `State<List<Item>>`. Neither backend
generates an array mirror, observer registry or synchronization adapter. Keys are injective stable strings derived
from declared identity. `JSON.stringify(item)` and the array index are not stable identity.

The app owns data delivery and native change notifications. `getData` has an explicit item type, and listener
registration/removal follows the platform contract. Replacing model data must update the app-owned data source and
notify ArkUI through that source (for example `onDataReloaded()` for a wholesale replacement). An ordinary `@Trace`
array or a whole-array `@Monitor` does not prove that in-place Array API calls or item replacement are observed;
v0 does not claim those mutations are supported. Incremental insert/move/delete delivery is generated only when the
model contract can describe it. Stable keys preserve logical row identity across a defined replacement, and the
source is not rebuilt in `build()`.

```ts
LazyForEach(this.model.items, (item: SettingItem) => {
  ListItem() {
    SettingRow({ item: item, onChange: this.onChange })
  }
}, (item: SettingItem): string => String(item.id))
```

**Fixture:** `Fixtures/performance/arkui-lazy-list/Expected.ets`.
**Reference:** [LazyForEach guidance](https://gitee.com/openharmony/docs/blob/master/en/application-dev/performance/lazyforeach_optimization.md).
**Measurement:** scroll frame p50/p99, component creation count, memory, replacement behavior.

### A3: reuse repeated, homogeneous list components

Decorate the repeated row's root `@ComponentV2` with `@ReusableV2`, available since API 18. API 12–17 screens keep
V2 observation but do not receive component-reuse generation; this is an explicit target-version capability, not a
V1 fallback. Use `.reuse({ reuseId: () => "setting" })` only for a real finite family of different row structures.
Do not nest reusable components or switch the reused subtree shape. V2 reuse automatically resets local state,
recomputes derived values and re-evaluates related monitors. Do not treat reuse as creation: required inputs must be
supplied at every call site, and any app-owned resources need the appropriate reuse/recycle lifecycle. The source-owned
`.contentType("setting")` operation on a direct generated List child supplies that literal reuse identity, as shown by
`Fixtures/child-view-layout-priority` and `Fixtures/child-view-foreach-content-type`; their ArkTS is not native-compiled
in this environment.

Reuse is particularly useful with `LazyForEach`, not with fully expanded `ForEach`. The target SDK must be API 18 or
newer for this rule; an older configured target leaves out `@ReusableV2` rather than emitting the incompatible V1
`@Reusable` decorator. No HarmonyOS toolchain is available here, so the fixture is a source-reviewed shape contract,
not compiler or runtime evidence.

**Fixture:** `Fixtures/performance/arkui-reuse/Expected.ets`.
**Reference:** [V1 reuse constraints](https://gitee.com/openharmony/docs/blob/master/en/application-dev/performance/component-recycle.md)
and [V2 `@ReusableV2` API/lifecycle](https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/state-management/arkts-new-reusableV2.md).
**Measurement:** node creation/reuse counts, scroll frame p50/p99 and memory.

### A4: shallow builders, narrow invalidation and direct callbacks

Emit flat, typed builders. Split a large repeated subtree into a named component only when that boundary supports
independent observation or reuse; splitting every tiny expression adds its own cost. Do not put expensive work,
mutable counters, array synchronization or resource lookup in `build()`, and do not nest `@Builder` functions just
to mirror the Swift syntax tree. A list action is a typed callback capturing only its item identity.

```ts
// A shallow repeated component; computation belongs in the app model.
Text(item.title)
Toggle({ type: ToggleType.Switch, isOn: item.enabled })
  .onChange((value: boolean): void => this.onChange(item.id, value))
```

**Fixture:** `Fixtures/performance/arkui-reuse/Expected.ets`.
**Reference:** [render-scope guidance](https://gitee.com/openharmony/docs/blob/master/en/application-dev/performance/precisely-control-render-scope.md).
**Measurement:** re-render count, CPU trace, frame p50/p99 and binary size.

## Measurement gate

Run generated and reference scenarios in the same build and environment. Use a release-like build with identical
shrinking, signing, profiling and compilation mode. `bench/android` currently disables shrinking to preserve both
variant boundaries; this limitation is included in the report. Startup uses cold starts and `CompilationMode.Partial`.
Frame scenarios use a defined scroll/update trace with at least ten iterations. Microbenchmarks use the same native
composable content and exclude setup from their timed region.

The Android report normalizes raw samples, reports nearest-rank p50/p99, and requires both variants for each
metric. It rejects mismatched contexts and missing samples. For lower-is-better latency metrics, a failure is a
change **greater than 5% AND greater than 0.1 ms**, for p50 or p99; both conditions avoid failing tiny absolute
noise or a large rounding change at a near-zero baseline. This is a screening gate, not permission to accept a
reproducible regression below it. Investigate regressions near the threshold with more iterations and a device run.
Memory, startup, recomposition and APK size are reported separately; averages never conceal a p99 regression.

Label every result **DEVICE** or **EMULATOR**, and include the model, OS/SDK, ABI, build type, dependency/toolchain
versions, compilation mode, runs and source revision. A headless software-emulator result is never a device result.
Raw AndroidX JSON and traces are retained alongside `report.json`/`report.md`. A compile-only run or an empty result
set is not a passing benchmark. See `bench/android/README.md` and `bench/harmony/README.md` for commands and the
HarmonyOS toolchain gap.
