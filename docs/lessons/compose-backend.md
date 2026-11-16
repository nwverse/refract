# Compose backend lessons

Pitfalls specific to emitting Jetpack Compose from the IR. Read this before touching `RefractCompose` or the
Compose examples, and add to it when something surprises you.

- **`Modifier` ordering matters.** Compose applies modifiers left to right, and `padding` before `background` is
  not the same as `background` before `padding`. The emitter preserves SwiftUI source order; never reorder for
  tidiness.
- **The root `modifier` parameter is special.** Only the outermost container receives the call-site `modifier`.
  Passing it to inner containers double-applies padding and breaks layout. See `nested-containers`.
- **`Button("Title") { action() }` collapses to `Button(onClick = action)`.** When the Swift action body is
  exactly one forwarding call, do not wrap it in a new lambda: that is an extra allocation and breaks Compose's
  skip. When the body is anything more, wrap in `remember(keys) { { … } }`.
- **`font` and `foregroundColor` are `Text` parameters, not modifiers.** Emitting them as `Modifier.*` calls does
  not compile. The split is part of the IR lowering, not a formatting choice.
- **Typed pattern lowering needs an explicit native scope.** Optional scalar aliases and single-payload enum cases
  are branch-local immutable values. Compose uses smart casts on a captured `when` subject; ArkTS uses documented
  null/undefined checks or class-union `instanceof` narrowing. Do not accept optional chaining, object payloads,
  arbitrary casts or shadowed bindings as an unvalidated shortcut.
- **`LazyColumn` keys are non-negotiable.** Without a stable `key` Compose cannot preserve row state or scroll
  position across updates, which is a silent performance regression. Refuse to emit a keyless list; `RF-C003`
  points the author at `Identifiable` or `id:`.
- **`contentType` is cheap and worth emitting.** When every row in a `LazyColumn` has the same static type, pass
  `contentType = { "TypeName" }`. Compose uses it to recycle composition, and the cost is one string constant.
- **No SF Symbols.** `Image(systemName:)` is Apple-only. Emit `RF-C002`, never a placeholder or a silently
  dropped `Image`.
- **Static lazy items still need identity.** A static list has no model id, but its generated `item` calls still need
  unique source-derived keys and a `contentType`. Do not mistake source position within a fixed section for permission
  to key a dynamic list by index. Check duplicate text keys and reject rather than aliasing rows.
- **Do not nest vertical `LazyColumn` in vertical scrolling `Column`.** This does not provide finite-height native
  scrolling. Emit `RF-C004` and ask for a single lazy list instead.
- **Application drawables need the app's `R` class.** Resolve `android.resources.className` from the mapping and
  import it. Do not guess a drawable package or invent a cross-platform symbol name.
- **Scope extensions need their receiver.** `Modifier.weight(1f)` resolves inside `RowScope`/`ColumnScope`; importing
  `androidx.compose.foundation.layout.weight` is not available to ordinary generated packages.
- **Text input is a typed value/callback boundary.** `TextField("key", text: $name)` needs a declared String
  `@State`/`@Binding` and a `LocalizedText` placeholder. Compose uses Material3 `TextField` with `label`; ArkUI uses
  `TextInput` with `placeholder` and `@Event` for parent bindings, never assignment to `@Param`. Reject other types
  and ad-hoc projected values rather than inventing writes.
- **Closing delimiters are part of golden correctness.** A composable call and a trailing closure have different
  closing shapes. Do not use a generic writer close for a plain `TextField(...)` call; validate actual generated
  syntax and compare both native goldens. Formatting-only changes must be reviewed in every affected fixture.
