# Native navigation graph pitfalls

- Parse the complete same-file View declaration table before resolving `navigationDestination` branches. A destination
  declared before its target View is still valid source; a traversal-order-only table misdiagnoses it as unknown.
  This is declaration resolution, not a runtime route registry, and does not replace the separately owned cross-file
  resolver.
- Post-parse graph binding must produce the `Module` returned by `Frontend.parse`. Mutating `Builder.screens` after
  constructing a local module and then returning the old value leaves the IR link present in debug output but missing
  from both generated targets. Keep the focused test's native-output assertions alongside the IR assertion.
- A source-only error recovery pass is diagnostic-only. When malformed link syntax produces no IR, the View still
  lacks its graph's host operation; report that independently with a source declaration coordinate rather than
  treating the invalid destination as a leaf. Do not generate partial output from that declaration.
- Native host tests cannot set content twice on one Compose activity, and a test rule without its own activity-scenario
  rule cannot use `activityRule.scenario`. For Robolectric recreation, retain the actual `ActivityController`, call its
  `recreate()`, and verify native state rather than replacing the controller with a source-owned route list.
- While resolving a destination switch, `currentStates` belongs to the enclosing root, not to the referenced
  destination. Check the destination's parsed `StateDeclaration` list instead. Scalar/form `@State` is destination-local,
  whereas `[Route]` state creates an unforwarded native callback and must be rejected as an unsupported nested stack.
- A golden fixture's HarmonyOS resource `catalog` is relative to the fixture root; repeat the form used by the existing
  navigation fixtures. Do not skip second-platform resource validation when the first target already generates.
