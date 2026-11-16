# ArkUI generation pitfalls

## An ArkTS interface does not enforce observation decorators

`@ObservedV2` belongs on the implementation class and `@Trace` on each observable property; neither can be a
requirement of a plain interface. `@Param` observes replacement of its value, not arbitrary class member mutation.
An app implementation therefore needs a documented decorator contract and an integration example. Do not generate a
plain model and claim it updates the UI. A `@Binding` maps to a `@Param` plus `@Event`, never assignment to the
`@Param`. `@Require` constrains constructor input, not a definite-initialization fallback for an uninitialized
`@Event`; use the documented empty callback initializer and always emit the parent's real callback.

## LazyForEach needs a native data source and stable identity

A Swift `ForEach` over identified data must not lower to the ordinary ArkUI `ForEach` when lazy rendering is part
of the subset contract. `List` + `LazyForEach` needs an `IDataSource`, a `ListItem` per datum and a stable string
key. Using the array index as a key can preserve state on the wrong row after insertion or deletion.

The application owns the data source; it is not generated as an array mirror or synchronization adapter. Give
`getData` an explicit item type, store listeners in a typed array, and guard listener registration and removal.
Replacement model data must update that app-owned data source and use its native change notifications. An ordinary
`@Trace` array or `@Monitor` watcher does not by itself prove that `LazyForEach` receives replacement notifications;
do not claim to observe in-place mutations of an ordinary app-owned array. The native compiler and an integration
example are still required to verify the concrete implementation.

## A Scroll has one child, and a component is not an entry page

A `Scroll` needs a single direct container, so a multi-child Swift `ScrollView` becomes `Scroll { Column { ... } }`.
Only the application owns its `@Entry` page. Generated reusable screens use `@ComponentV2` and are callable from
ordinary native navigation without a host or global initialization.

## Declarative builders are not ordinary closures

Do not add an ordinary `: void` return annotation to a trailing UI-builder closure merely to satisfy a textual ArkTS
style rule. Component `build()` methods are annotated, while builder syntax and its permitted annotations must be
checked against actual ArkUI SDK examples and the compiler. A syntactic TypeScript parse alone is not verification.

## Emit errors, not commented placeholders

An unsupported node, unknown modifier or untyped list is a build-time diagnostic with a stable code and source
location. Never emit `// Unsupported` inside an otherwise successful `.ets` file and never substitute an empty
string for an expression. The public generation API must expose those diagnostics to the CLI/golden runner rather
than returning only a string.
