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
- **`KeyboardOptions(autoCorrect = ...)` is deprecated in recent Compose BOMs.** The constructor warns at
  `:fixtures:compileDebugKotlin`. Use `autoCorrectEnabled = false` for the password keyboard on `SecureField`;
  the previous spelling still compiles but adds a deprecation warning to every consumer.
- **`SecureField` must stay a native `TextField`, not a custom composable.** Wrapping a basic `TextField` in a
  hand-rolled "secure" composable duplicates autofill and IME wiring that the platform already owns. The
  generator's job is `visualTransformation` and `keyboardOptions`, not a parallel secret input pipeline.
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
- **Parenthesized calls close with `)`, not `}`.** `NavigationBarItem(...)`, `DropdownMenuItem(...)` and similar
  composables take their content as named lambda arguments inside parentheses. A generic writer `close()` emits `}`,
  which is a syntax error ("Expecting ')'"). Use a dedicated `closeParen()` for `open("Name(")` calls, and never put
  a trailing comma after the last named lambda argument before `)`. Compile generated Kotlin through
  `:fixtures:compileDebugKotlin` rather than trusting a source read; a hand-written probe file is easy to typo and
  can send you chasing the wrong bug.
- **Non-composable lambdas cannot call composable functions.** `Modifier.semantics { contentDescription = ... }`
  runs outside composition, so `stringResource(...)` must be read into a local `val` in composable scope first and
  captured. The Kotlin compiler reports "@Composable invocations can only happen from the context of a @Composable
  function".
- **Material icon symbols need an explicit dependency.** `Icons.Default.*` lives in
  `androidx.compose.material:material-icons-core`, which is not pulled in by `material3` alone in this build. A
  `symbols` mapping of kind `materialIcon` must be matched by the consuming module's dependency.
- **Icon-only buttons need an accessibility label.** A generated `IconButton` with only an icon has no text for
  screen readers or for `onNodeWithText` lookups. Put the localized label on the button as `contentDescription`
  (see above), which also gives native tests a stable selector.
- **Trailing-closure writer operations must be balanced.** `KotlinWriter.open("Name(")` increments depth by one for
  the parenthesized argument list; `closeParenAndOpenBody("param")` decrements depth (closing the paren) and
  increments it again (opening the trailing closure body). The caller must then call `close()` exactly once per
  `open`/`closeParenAndOpenBody` pair. Manually adjusting `out.depth` is fragile and leads to negative-count crashes.
  If the nesting pattern is new, extract a helper rather than guessing depth offsets.
- **Sectioned horizontal lists need one vertical lazy owner.** `LazyColumn` owns the vertical axis; each section
  row is a `Column` with a header and a `LazyRow`. The `LazyRow` is the horizontal scroll container; it does not
  create a second vertical owner. In ArkUI the outer `List` holds `LazyForEach`; each section row is a
  `ListItemGroup` wrapping a `ListItem` with a `LazyRow(Scroller())`. The `LazyForEach` keyGenerator is the third
  argument to `LazyForEach` (after the item builder closure), not inside `ListItemGroup`.
- **Recognition gates must not emit diagnostics for non-matching shapes.** When adding a new frontend recognizer
  that hooks into an existing path (e.g. `ForEach` inside `List`), return `nil` silently when the shape does not
  match. Only emit a diagnostic once the recognizer has committed to handling the construct. Otherwise every
  ordinary `ForEach(model.items)` will produce a false diagnostic.
