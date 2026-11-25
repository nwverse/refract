# Accessibility semantics pitfalls

- Compose `Modifier.semantics` and `CustomAccessibilityAction` callbacks are not composable. Do not put
  `stringResource` inside them. Read localized text in composition and expose the current String through
  `rememberUpdatedState`, otherwise Kotlin compilation fails with `COMPOSABLE_INVOCATION`.
- Compose `hintText` belongs to editable fields; it is not a generic `accessibilityHint`. ArkUI
  `accessibilityTextHint` is documented primarily for vehicle accessibility services. Use native supplementary
  descriptions and state descriptions instead, and document the speech-behavior difference.
- A parent `isTraversalGroup` is not a semantic merge. Compose compares traversal indices within the native
  traversal-group scope; a merging actionable child carries its own group/index metadata. Do not add
  `mergeDescendants` to an entire stack just to make a test pass: it can hide separately actionable children.
- ArkUI `accessibilityNextFocusId` points from a predecessor to its successor, not from a child to its predecessor.
  Validate the complete acyclic source-order chain before emitting ids. Do not insert the current name into the
  predecessor set before validating `after`: that turns a self-reference into an apparently earlier predecessor.
  Test the frontend's typed IR directly as well as the CLI; backend rejection can mask a frontend acceptance bug.
- `accessibilityStateDescription` (API 23), `accessibilityCustomActions` (API 26) and
  `accessibilityNextFocusId` (API 18) must be gated by an explicit consumer `minimumAPI`. Missing version evidence
  is a build-time diagnostic, never a reason to drop an accessibility operation silently.
- Reordering accessibility metadata is not the same as reordering drawing, keyboard focus or screen-reader speech.
  Compose Native JVM metadata and captures are useful local evidence but cannot establish TalkBack/VoiceOver/ArkUI
  device behavior. Preserve those limits in docs and PRs.
- Native test helpers must use the platform's actual semantics key types: Compose content descriptions are
  `List<String>` (not `AnnotatedString`), and custom actions use `SemanticsActions.CustomActions`, not the similarly
  named `SemanticsProperties` key. Locale qualifiers in Robolectric use resource order such as `en-rES-...`.
  When testing two font scales, use isolated composition roots rather than leaving duplicate tagged nodes mounted.
