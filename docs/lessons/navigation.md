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
- A golden fixture's HarmonyOS resource `catalog` is relative to the fixture root; repeat the form used by the existing
  navigation fixtures. Do not skip second-platform resource validation when the first target already generates.
- A qualified destination link carries a conventional `path` placeholder until the frontend's graph binding supplies
  `Screen.navigation`. ArkUI must resolve that placeholder only for a destination registered by the matching root
  stack; treating the literal `path` as a backend-wide wildcard accepts inconsistent decoded or manually constructed
  IR. Compare the root, destination and link operations and fail with `RFNAV003` when any is missing or mismatched.
- Cover a non-default path name in source and golden tests. Default-only coverage lets a correctly declared
  `onRoutePathNavigate` coexist with stale `onPathNavigate` calls and forwarding.
