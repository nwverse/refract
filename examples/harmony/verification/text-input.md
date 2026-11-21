# Native committed-draft text-input verification

## Current status: source-prepared and blocked

`NativeTextInputHost.ets` is a concrete app-owned ArkUI implementation, not a Refract runtime or a generated template.
The exact shared Swift `InteropTextInputHost.swift` produces the checked-in `InteropTextInputHost.ets`; the separate
`ComposerTestAbility` loads a native parent that calls that generated component. No replacement composer is used.

**No source here has been compiled or executed on HarmonyOS.** This checkout has no authorized DevEco CLI, matching
SDK, signing workflow, `hdc` or owned simulator/device. No real Chinese IME, candidate selection, keyboard window,
callback order or draft persistence has been observed. The static checks below are source contracts only. See
[the text-input design](../../../docs/text-input-host.md) and [the exact toolchain blocker](../../../docs/harmony-toolchain.md).

## Portable source/golden checks

From the repository root after `swift build`:

```sh
python3 scripts/check_examples.py
python3 -I scripts/check_harmony_text_input.py
python3 -I scripts/test/test_harmony_text_input.py
python3 scripts/check_harmony_toolchain.py --check-only
```

The example check uses the real CLI and committed expected output. The static checker and its 24 negative/scenario checks
cover the host ABI, mounted/editing-session invalidation, delayed-callback rejection, parent updates during preview,
unique focus identity, actual focus-transfer scaffolding, actual `SubmitEvent.text` and main-control-flow callback
order. One mutation moves commit calls into the active-preview branch and must fail even though their textual order is
unchanged. These checks do not parse or execute ArkTS. The preflight currently returns 2 for the missing authorized
toolchain; that is the expected blocker, not a passing native build.

## Authorized native checks still required

Follow the toolchain guide to build the application and `entry@ohosTest` in separate invocations. The checked-in
`ComposerTestAbility.ets` registers `GeneratedComposer.test.ets` and loads `GeneratedComposerHost.ets` through
`test_pages.json`; `module.json5` registers that separate ability. Do not replace it with the settings ability.

On an explicitly allocated, signed target, launch `ComposerTestAbility` rather than `TestAbility`. Record the exact
module/ability invocation supplied by the authorized SDK tooling; no native execution command is claimed to have run
here. The source-prepared Hypium/UI Test case exercises committed text injection, two distinct generated editors,
per-instance focus tokens, an explicit transfer to another native focus target with `isFocused` assertions,
removal/restoration of one generated composer and hardware Enter. `inputText()` is not a Chinese IME test and
must not be used to claim preedit or candidate compatibility.

Then perform and record the following with a named real Chinese IME and exact OS build:

1. Focus through a new token and type Pinyin until native preview is visible. Confirm no preview string reaches the
   parent draft or submitted model. Change the parent draft during preview: the new parent value must survive, native
   editing must end with an explicit diagnostic, and any delayed old-session callback must not publish or submit.
2. With an unchanged parent and a fresh active editing session, select a candidate in the native IME. Verify only its
   actual committed value reaches the parent; no host-side Pinyin translation, synthetic candidate or composition
   mirror is permitted.
3. With preview active, press Done. Require the visible candidate-selection diagnostic and zero commit callbacks;
   native editing and preview must remain available. Select the actual candidate, press Done again and require one
   committed-draft callback followed by focus/keyboard exit and one application commit, in that order.
4. Repeat with hardware Enter. Exercise actual focus loss to another native control and restoration with a new token,
   then remove/restore the composer and verify delayed callbacks from its old mount cannot publish. With two generated
   editors mounted, require distinct native IDs and verify each focus token focuses only its own editor. Confirm the
   application-retained committed draft and submitted value remain intact.
5. Save the native console/test output privately, inspect the visible diagnostics and record whether the target was a
   simulator or physical device. Any mismatch is a native compatibility blocker, not permission to skip the assertion
   or replace it with static output.

No performance claim or rendered screenshot evidence is supplied by this preparation slice. Umbrella #245 stays open
until its native acceptance is actually satisfied.
