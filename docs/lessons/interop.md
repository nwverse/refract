# Native interop pitfalls

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
- In a modifier `while` loop, even an operation that emits no chain must advance the index before `continue`.
  Otherwise a retained callback can make generation spin instead of producing output or a diagnostic.
