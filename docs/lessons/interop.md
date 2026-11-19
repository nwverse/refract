# Native interop pitfalls

- SwiftSyntax parsing does not prove SwiftUI type correctness. `Binding(get:set:)` is a real SwiftUI initializer, but
  `.refractNativeModifier(...)` and `.padding(horizontal:vertical:)` require explicit iOS-only source declarations.
  Compile uniquely named source-only inputs for the measurement contract, with byte-identity checks against the
  canonical fixtures and their application-owned design tokens. Several `Input.swift` file references collide on
  Xcode's `Input.stringsdata` even when their display names differ; real Xcode builds catch this before type checking.
- Prefer correcting pseudo-SwiftUI over adding a compatibility shim for it. `Button(verbatim:)` is not SwiftUI;
  use the ordinary action/label pair with `Text(verbatim:)` and reject the invalid initializer with a source-located
  diagnostic. The typed interop helpers above are different: they carry declared platform-only semantics while
  preserving the receiver's native iOS view behavior.
- An iOS-only native body may read accessibility preferences without adding them to the generated interface. The
  narrowly accepted `accessibilityReduceMotion` environment property is not an argument; do not turn it into a shared
  animation flag or allow arbitrary property wrappers to bypass native-signature validation.
- Test observation must not alter the generated interface. A host `CompositionLocal` around the unmodified generated
  caller can supply an app-owned observer; rewriting generated Kotlin to add a test callback would no longer test the
  actual contract. Compose transition assertions should inspect public transition/idle state, not an invented
  semantics-alpha property.
- Resolve a native scalar member argument against declared models before leaving its type unknown. `model.identity`
  is a typed model value on both backends; an undeclared item/model member must still produce only its original
  diagnostic, not a second inferred-type error.
- Stateful native transitions belong in app-owned native implementations. A Compose `Animatable` retains its current
  value when the keyed effect cancels and starts a new target; `key(identity)` must scope the animation and effects,
  and reduced motion must snap rather than adding a parallel duration policy. Read frame progress in a native draw
  lambda, not a parent-composition state read.
- Compose UI tests with a manual clock must distinguish starting an animation from advancing its progress, and must
  apply composition frames explicitly after input changes. Do not assume `runOnIdle` creates a frame when no
  animation is awaiting one. Observe actual `Animatable.value`/`isRunning` and identity disposal, not an invented
  cross-platform cancellation event or wall-clock timing.
- AGP 9's built-in Kotlin support does not automatically consume a custom `sourceSets.main.java` directory. Register
  an application-owned Kotlin implementation through `sourceSets.main.kotlin.directories` when compiling a fixture
  import; adding only a dependency or generated import does not put its source on the compiler input list.
- A mapping may use the normalized native-only compatibility form. The fixture compilation script must use the same
  `refract.generated` default package as the Compose backend rather than indexing a full mapping's `android.output`
  unconditionally.
- Keep IR independent of mapping and backends. Interop lowering helpers belong in `RefractMapping` or a backend;
  importing `RefractMapping` from `RefractIR` creates a circular module dependency.
- A native view argument needs its label and source type, not only an expression. Unknown reference types must not be
  invented as `String`; wait for typed state/model resolution or issue a diagnostic.
- A structured native selection value belongs in the existing typed `NativeArgument` channel, not a new general
  payload ABI. Keep static literal ranges validated in UTF-16, including empty selections and surrogate-pair
  boundaries, and forward context snapshots to declared scalar model actions. Do not add arbitrary Screen closures,
  selection callbacks on movement or a URL-opening side effect. See `docs/selection-link-context.md`.
- Validate a target at its call site. Having both backends validate both targets repeats the same missing/mismatched
  mapping diagnostic. Drivers collect independent target errors before writing either output.
- Do not infer an ArkTS `number` parameter from the corresponding Kotlin type: Kotlin `Int` and `Double` both map to
  `number`. Preserve the target spelling and compare it with the Swift declaration.
- Compose's root `Modifier` belongs on the generated root view. Forward it to a native child only if the mapping
  explicitly declares a modifier parameter; not every application-owned composable accepts one.
- Platform view alternatives use independent Swift generic view types. Do not introduce `AnyView`; select one
  complete subtree per backend, without a runtime branch or a wrapper container.
- Keep hand-written native caller files in the fixture, but test their imports and invocations explicitly. Their mere
  presence does not establish goal 5 coverage. Platform compiler builds are separate evidence and must not be claimed
  from text comparisons.
- Platform-selected strings need explicit provenance. A bare `Text(refractValue(ios:android:harmonyOS:))` would
  feed SwiftUI's `Text(_: LocalizedStringKey)` initializer on iOS, silently treating the iOS branch as a localization
  key while the native backends emit their branch as a verbatim literal. The accepted form is
  `Text(verbatim: refractValue(...))`: every branch is a string literal and iOS selects `Text(verbatim:)`, so all
  three platforms agree on verbatim semantics with no runtime adapter. Reject the bare localized form with a
  source-located `R.string.unsupported_expression` diagnostic that names the divergence and points to the verbatim
  form, rather than silently emitting per-platform localization keys or unverified resource lookups.
- Native measurement operations belong on the measured native control, not an enclosing layout Row. Keep toggle
  native metadata typed until its emitter can place the modifier on Switch/Toggle itself.
- Retained callback keys include every captured stable value. A source action name is a discriminator, not a
  substitute for the current model or the list item's declared `Identifiable` id.
- A generated child call needs an ordered typed argument list with the child's label and the caller's expression.
- Typed navigation must not synthesize a second back stack. `@State [Route]` owns the iOS path, while generated
  Android/HarmonyOS roots expose a finite-enum navigation callback and the host owns its controller/stack. Compile a
  real `NavHost` host alongside the generated two-screen components; merely finding `NavController` in documentation
  proves nothing. A generated link is a child of its root container: forward the host modifier only to that container,
  not to every nested Button/Text, and scope each link callback to its own path rather than the first navigation
  screen in the module. Keep the destination component's model parameters in the root screen's scope, not all module screens.
  When native destinations live in IR rather than ordinary `.native` nodes, collect their typed imports before the
  ArkUI header is emitted, and include them in the platform compiler's fixture manifest.
- A generated child call needs an ordered typed argument list with the child's label and the caller's expression.
  Kotlin named arguments use `label = value`, not Swift's `label: value`; ArkTS uses `label: value` in its object
  literal. Golden text alone does not catch that distinction, so compile a child call whose model label differs
  from the caller's model name. Resolve each View's immutable inputs in local scope and restore the caller's
  item/model context after its body; a child's item alias is not the parent's `LazyForEach` item.
- In a modifier `while` loop, even an operation that emits no chain must advance the index before `continue`.
  Otherwise a retained callback can make generation spin instead of producing output or a diagnostic.
- A row content type belongs to the generated child directly owned by either canonical dynamic List form. Preserve
  the declaration in the `ForEach` `ListItems` constructor as well as the shorthand constructor, and reject page-level
  or nested children before either backend emits. An invalid content type is never a retained-callback operation.
- Hidden Toggle labels remove the visible title and its layout wrapper, not the title's typed getter/action checks,
  native accessibility, measurement modifiers or `remember(model, row.id)`. Inspect both output paths for duplicate
  wrappers rather than relying on an unused `title` variable to prevent one.
  select the node that defines `SemanticsActions.Dismiss`, not an arbitrary `onRoot()`.
- Selection editing and drag/drop payloads on a `TextField`/view go through the closed `NativeModifier.Operation`
  set, not through a generic native component. The Compose drag-and-drop API lives in
  `androidx.compose.foundation.draganddrop` for the `Modifier` extensions but in
  `androidx.compose.ui.draganddrop` for the `DragAndDropEvent`/`DragAndDropTarget`/`DragAndDropTransferData`
  types — importing them from `foundation.draganddrop` produces "Unresolved reference" at Kotlin compile
  time even though the golden fixture text looks right. Always compile the new fixture before declaring
  the operation ready, and opt in via `@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)`
  on the generated file. Drop-target cancellation is gated on the payload string, not on the event: the
  generated wrapper checks `payload.isEmpty()` and returns `false` before the model action is invoked,
  so a cancelled drop never reaches the model. Unicode (non-BMP emoji + CJK) round-trips through
  `ClipData.newPlainText` unchanged; do not introduce a "safe ASCII" encoding — the typed String payload
  is the contract.
