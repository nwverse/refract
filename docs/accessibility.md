# Native accessibility: text, actions and traversal

Refract exposes bounded native accessibility semantics in the shared Builder/IR. It does not create an accessibility
runtime, a parallel accessibility tree, screen-specific strings or a replacement native control. Generated labels,
values and action names resolve through the application's localized resources on both platforms.

The source contract and diagnostics are normative in `docs/subset.md`; this document records platform trade-offs and
the evidence boundary for issue #226. #165 owns dynamic-type lowering; #209 owns token/theme interaction states. This
work does not change either registry or its fixtures.

## Text provenance and meaning

`.accessibilityLabel(Text("accessibility.key"))`, `.accessibilityHint(Text(...))` and
`.accessibilityValue(Text(...))` use ordinary SwiftUI `Text`. A static string is a canonical localization key, with
the same typed interpolation and resource checks as visible `Text`. Verbatim accessibility text is rejected. The
existing model-backed `String` overload of `accessibilityLabel` remains supported: the application model owns its
localized value. Custom action names require a static localized `Text` key.

These values do not have identical native meanings on every platform:

| SwiftUI value | Compose | ArkUI |
| --- | --- | --- |
| Label | `contentDescription` | `accessibilityText` |
| Supplementary hint | Additional, space-separated `contentDescription` | `accessibilityDescription` |
| Current value/state | `stateDescription` | `accessibilityStateDescription`, API 23+ |

Compose's `hintText` is for editable-input guidance, not a generic accessibility hint; it is not used as a substitute.
ArkUI's `accessibilityTextHint` is documented primarily for vehicle accessibility services and is also not treated as
a universal hint. Compose has no direct generic supplementary-hint property, so label and supplementary description
are joined in source order. This is an explicit native mapping, not a claim that VoiceOver, TalkBack and ArkUI screen
readers produce identical speech. Device-specific pronunciation, grouping and ordering remain to be verified on the
consumer's supported platforms.

A native control retains its checked/editable state and ordinary activation callback. A custom value supplements, not
replaces, the native state. The generator does not merge unrelated labels and controls or merge an entire stack to
make its output look more accessible.

## Custom actions

`.accessibilityAction(named: Text("accessibility.action")) { model.syncNow() }` is lowered to:

- Compose `customActions = listOf(CustomAccessibilityAction(label: ...) { model.syncNow(); true })`.
- ArkUI `.accessibilityCustomActions([{ name: ..., onAction: ... }])`, API 26+.

The closure accepts the same typed synchronous model action or scalar local-state mutation as a normal Button
action. There is no arbitrary callback lookup, async operation, runtime action registry or hidden state mutation.
The action reports successful handling to Compose only after that typed callback returns. Ordinary visible buttons
remain the accessible alternative to a custom action; a custom action does not replace normal click activation.

On Compose, localized text is read with `stringResource` in composition and exposed to semantics/action lambdas via
`rememberUpdatedState`. This is necessary because those lambdas are not composable. The current locale and model
arguments therefore update the exposed text without capturing stale strings or adding a Refract runtime.

ArkUI's array API supports at most 16 actions per component in the referenced contract. The current bounded slice
accepts one named action per source modifier and one action modifier per receiver; multiple action modifiers on one
receiver are rejected rather than emitted as an ambiguous list. Applications should keep this list small and
meaningful. The HarmonyOS compiler/runtime still has to verify the consumer's API level and behavior.

## Bounded traversal

There is no universal numeric priority that has identical semantics on iOS, Compose and ArkUI. In particular, iOS
sorts larger priorities first, Compose sorts smaller traversal indices first, and ArkUI links a node to its next
accessibility focus. The shared source therefore uses the existing declared `refractView` platform-variation form:

- iOS uses ordinary `.accessibilitySortPriority(...)` in its branch. This is standard SwiftUI, not a fabricated
  modifier. Its implementation is not verified on macOS in this environment.
- Android/HarmonyOS branches may put `.accessibilityTraversal([...])` on a direct stack. Entries use
  `.accessibility("name")` or `.accessibility("name", after: "predecessor")` and refer to literal
  `.accessibilityIdentifier("name")` values on direct Button, Toggle, TextField or Image children. Every named
  actionable direct child must appear exactly once. A forward/cyclic predecessor, duplicate identifier, unknown name
  or identifier on a decorative/non-merging container is a build-time error rather than a best-effort order.

On Compose the stack emits `isTraversalGroup = true`; named actionable children emit their own
`isTraversalGroup = true` and zero-based `traversalIndex` because their native semantics already merge descendants.
No `mergeDescendants` is added to the stack merely to manufacture accessibility evidence. iOS's identifier remains a
native testing/accessibility identifier; on Compose the same source identifier is emitted as `testTag`, while ArkUI
emits `id` only where its traversal contract requires it. ArkUI emits `accessibilityNextFocusId` on the predecessor,
pointing to the named successor (API 18+). The source sequence is not a visual/drawing reorder, keyboard-focus
promise or general nested traversal language. Natural order remains preferable whenever the source layout already
matches reading order.

`harmonyOS.minimumAPI` is an additive optional mapping field for the application's minimum native SDK/API level.
Existing mappings remain valid. The generator emits gated calls only when the declared minimum meets the actual API
requirement: traversal links 18, state descriptions 23, custom actions 26. A missing or lower value produces
`RFACCESS005` and no successful output; it never silently drops an operation or pretends a lower-level fallback is
equivalent. Mapping consumers must match this declaration to their native project settings.

## Evidence and limits

`Fixtures/accessibility-actions-traversal/` contains one SwiftUI input with an explicit iOS branch and dual-backend
native branches. It generates reviewed Compose and ArkTS sources through the real CLI, registers with the golden
corpus and Android compilation gate, and supplies base English plus Spanish app resources. The golden is not a claim
that iOS compilation or HarmonyOS runtime behavior was observed.

The fixture's exact CLI-generated Kotlin is staged into the app's real resource namespace by
`scripts/check_fixture_compilation.py`. `GeneratedAccessibilitySemanticsTest` uses Compose on Robolectric with
native graphics to check:

- localized labels/state/action names and an updated model-backed state description;
- custom-action invocation and ordinary click alternatives;
- direct-child traversal metadata and unmerged/merged semantics trees;
- Spanish resource rendering;
- `fontScale = 2.0` native rendering, nonzero control bounds and a nonempty capture.

**These are Native JVM Compose results, not emulator, device or screen-reader evidence.** Captures and semantics
reports are written under `app/build/reports/native-jvm-compose/` and published by the existing CI job. The large
text capture was inspected: the text grows, wraps and remains visible in the capture; this does not prove every
consumer layout or dynamic-type setting. No performance or device-rendering parity measurement is inferred.

Not verified in this environment: SwiftUI compilation and VoiceOver on macOS/iOS; ArkTS compilation and ArkUI screen
reader behavior on HarmonyOS; Android emulator/device TalkBack traversal, actual spoken hints and focus behavior.
Those remain native integration checks for provisioned targets. The generator cannot prove screen-reader behavior
from a JVM semantics tree.
