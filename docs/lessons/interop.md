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
- Keep IR independent of mapping and backends. Interop lowering helpers belong in `RefractMapping` or a backend;
  importing `RefractMapping` from `RefractIR` creates a circular module dependency.
- A native view argument needs its label and source type, not only an expression. Unknown reference types must not be
  invented as `String`; wait for typed state/model resolution or issue a diagnostic.
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
- Native measurement operations belong on the measured native control, not an enclosing layout Row. Keep toggle
  native metadata typed until its emitter can place the modifier on Switch/Toggle itself.
- Retained callback keys include every captured stable value. A source action name is a discriminator, not a
  substitute for the current model or the list item's declared `Identifiable` id.
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
