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

The example check uses the real CLI and committed expected output. The static checker and its negative mutations cover
the host ABI, preview isolation, external-update suppression during preview, focus tokens, actual `SubmitEvent.text`,
commit/focus/callback order, explicit active-preview diagnostics and the generated-parent wiring. They do not parse or
execute ArkTS. The preflight currently returns 2 for the missing authorized toolchain; that is the expected blocker,
not a passing native build.

## Authorized native checks still required

Follow the toolchain guide to build the application and `entry@ohosTest` in separate invocations. The checked-in
`ComposerTestAbility.ets` registers `GeneratedComposer.test.ets` and loads `GeneratedComposerHost.ets` through
`test_pages.json`; `module.json5` registers that separate ability. Do not replace it with the settings ability.

On an explicitly allocated, signed target, launch `ComposerTestAbility` rather than `TestAbility`. Record the exact
module/ability invocation supplied by the authorized SDK tooling; no native execution command is claimed to have run
here. The source-prepared Hypium/UI Test case exercises committed text injection, a focus token, another focused
control, removal/restoration of the generated composer and hardware Enter. `inputText()` is not a Chinese IME test and
must not be used to claim preedit or candidate compatibility.

Then perform and record the following with a named real Chinese IME and exact OS build:

1. Focus through a new token and type Pinyin until native preview is visible. Confirm no preview string reaches the
   parent draft or submitted model. Change the parent draft during preview and verify it does not replace that preview.
2. Select a candidate in the native IME. Verify only its actual committed value reaches the parent; no host-side Pinyin
   translation, synthetic candidate or second composition mirror is permitted.
3. With preview active, press Done. Require the visible candidate-selection diagnostic and zero commit callbacks;
   native editing and preview must remain available. Select the actual candidate, press Done again and require one
   committed-draft callback followed by focus/keyboard exit and one application commit, in that order.
4. Repeat with hardware Enter. Exercise focus loss/restoration, remove and restore the composer, and confirm the
   application-retained committed draft and submitted value remain intact.
5. Save the native console/test output privately, inspect the visible diagnostics and record whether the target was a
   simulator or physical device. Any mismatch is a native compatibility blocker, not permission to skip the assertion
   or replace it with static output.

No performance claim or rendered screenshot evidence is supplied by this preparation slice. Umbrella #245 stays open
until its native acceptance is actually satisfied.
