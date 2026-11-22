# ArkUI generation pitfalls

## An ArkTS interface does not enforce observation decorators

`@ObservedV2` belongs on the implementation class and `@Trace` on each observable property; neither can be a
requirement of a plain interface. `@Param` observes replacement of its value, not arbitrary class member mutation.
An app implementation therefore needs a documented decorator contract and an integration example. Do not generate a
plain model and claim it updates the UI. A `@Binding` maps to a `@Param` plus `@Event`, never assignment to the
`@Param`. `@Require` constrains constructor input, not a definite-initialization fallback for an uninitialized
`@Event`; use the documented empty callback initializer and always emit the parent's real callback.

## Nested local bindings need cumulative scope

An optional or enum-payload binding name is not the only local name available to its descendants. A nested binding or
container must retain the outer aliases; replacing that one-name context makes a later Boolean condition incorrectly
emit `this.alias` instead of `alias`. Keep lexical aliases cumulative through recursive emission and test both aliases
in a nested container. Removing an inner alias at its native `else` boundary must not remove an outer one. Pass the cumulative
set through Text expression lowering too: `LazyForEach` must add its row item without hiding an outer optional alias.
A Text leaf that ignores this set emits `this.alias` even though recursive container and condition paths are correct.
Apply the same set to modifier expression lowering: a `LazyForEach` row's `accessibilityLabel(Text(alias))` must not
replace the outer optional alias with the row item. Test the modifier on both Text and Button while retaining the
Text leaf's local reference; rejected dynamic stack arguments are not alias-scope coverage.
Event payload lowering needs the same set: retaining it only for the wrapped Text is insufficient when `onDragStart`
reads an optional scalar, because that separate expression would incorrectly emit `this.alias` for a local binding.

## A declared item input is not a lazy-row local

A generated child View can receive an `Identifiable` item as a stored input. ArkUI declares that input as `@Param`,
so its Toggle value and model-action identity must read `this.row.enabled` and `this.row.id`, just as its ordinary
Text and measurement expressions read `this.row`. Only a current `LazyForEach` closure owns the unqualified local
`row`. Distinguish the two scopes explicitly; a type match or identical property name does not make a component
parameter a builder-local value. A current horizontal `ForEach` row with the same name shadows that parameter: both
the Toggle value and model-action identity must use the active local, so apply `this.` only when no local alias owns
the name. Regenerate every committed artifact derived from the changed lowering: the Fixtures
goldens and the separate `bench/harmony/generate.py` output, whose `--check` must also remain byte-exact.

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

A specialized dynamic-section lowering must retain the same outer `List()` as the ordinary `.list` path. Emitting its
`LazyForEach` directly in `build()` drops the only vertical owner and can pass source-only golden tests while producing
an invalid component structure. Prefer routing specialized children through the shared List wrapper; review the
resulting `LazyForEach` keyGenerator position and `ListItemGroup` nesting. This source review is not ArkTS compiler
verification.

## A Scroll has one child, and a component is not an entry page

A `Scroll` needs a single direct container, so a multi-child Swift `ScrollView` becomes `Scroll { Column { ... } }`.
Only the application owns its `@Entry` page. Generated reusable screens use `@ComponentV2` and are callable from
ordinary native navigation without a host or global initialization.

## A typed layout must retain the row type, not only its local name

A `LazyForEach` row has both a local name and an item type. ArkUI's typed-layout recursion must retain both when a
`VStack(spacing:)` contains an item Toggle. Passing only the local name leaves the model-action projection guard
without its row type and rejects an accepted input with `state.invalid_projection`. Keep this context propagation
separate from conditional recursion and receiver selection, and cover the exact path with paired output. When that
golden joins the shared Android fixture compile set, give it a unique package if another case declares the same model
type; independent CLI regeneration cannot detect a cross-fixture Kotlin `CLASSIFIER_REDECLARATION`.

## Declarative builders are not ordinary closures

Do not add an ordinary `: void` return annotation to a trailing UI-builder closure merely to satisfy a textual ArkTS
style rule. Component `build()` methods are annotated, while builder syntax and its permitted annotations must be
checked against actual ArkUI SDK examples and the compiler. A syntactic TypeScript parse alone is not verification.

## Local scalar aliases do not disable canonical modifiers

A list item or optional/payload binding alias is an expression-scope input, not a reason to bypass canonical modifier
lowering. `Text(alias).frame(width: 44)` must produce `.width(44)` with the local alias, just as an ordinary scalar
Text does. Keep expression-name resolution separate from the decision about which modifier forms are supported, and
test aliases in optional and payload branches through the actual CLI on both backends.

## Emit errors, not commented placeholders

An unsupported node, unknown modifier or untyped list is a build-time diagnostic with a stable code and source
location. Never emit `// Unsupported` inside an otherwise successful `.ets` file and never substitute an empty
string for an expression. The public generation API must expose those diagnostics to the CLI/golden runner rather
than returning only a string.
