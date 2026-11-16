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
- **`if let x = x` is just `if (x != null)`.** Kotlin's smart cast does the binding for you. Only when the Swift
  side introduces a *new* name does the emitter need `?.let { }`.
- **`LazyColumn` keys are non-negotiable.** Without a stable `key` Compose cannot preserve row state or scroll
  position across updates, which is a silent performance regression. Refuse to emit a keyless list; `RF-C003`
  points the author at `Identifiable` or `id:`.
- **`contentType` is cheap and worth emitting.** When every row in a `LazyColumn` has the same static type, pass
  `contentType = { "TypeName" }`. Compose uses it to recycle composition, and the cost is one string constant.
- **No SF Symbols.** `Image(systemName:)` is Apple-only. Emit `RF-C002`, never a placeholder or a silently
  dropped `Image`.
