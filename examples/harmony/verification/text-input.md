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
python3 -I scripts/test/test_harmony_composer.py
python3 scripts/check_harmony_toolchain.py --check-only
```

The example check uses the real CLI and committed expected output. Its source-contract negatives and the static host
checks cover the host ABI, mounted/editing-session invalidation, delayed-callback rejection, parent updates during preview,
unique focus identity, actual focus-transfer scaffolding, actual `SubmitEvent.text` and main-control-flow callback
order. The separate `scripts/test/test_harmony_composer.py` checks the fail-closed native execution/report contract:
only the selected `GeneratedComposer` case can pass, and a successful settings-suite output cannot substitute for it.
It also pins suite/host selection and a report whose IME/render/performance flags remain false. These are portable
Python checks using synthetic protocol output and mocked commands, not ArkTS execution or native test evidence.

The real entry uses the documented `AbilityDelegatorArgs.parameters` dictionary. Both bounded native runners pass
`refractSuite` explicitly. `TestAbility` registers exactly the selected settings or composer suite and loads its
matching generated host; an unsupported selection throws instead of silently running another screen. The separate
`ComposerTestAbility` remains an explicitly source-prepared manual test entry, not a target selected by the runner.

## Authorized native checks still required

Follow the toolchain guide to prepare the application and `entry@ohosTest` build targets in separate invocations. The
checked-in `ComposerTestAbility.ets` registers `GeneratedComposer.test.ets` and loads `GeneratedComposerHost.ets`
through `test_pages.json`; `module.json5` registers that separate ability. Do not replace it with the settings ability.
Keep every native build and its execution under `CPUQuota=200% MemoryHigh=5G MemoryMax=6G TasksMax=512`, for example
through `systemd-run --user --scope` on the allocated Linux host. Do not run a concurrent Gradle build.

On an explicitly allocated, signed target, run the bounded committed-draft execution entry from a clean repository
root. It builds both HAPs itself and installs private snapshots of those exact outputs:

```sh
systemd-run --user --scope \
  -p CPUQuota=200% -p MemoryHigh=5G -p MemoryMax=6G -p TasksMax=512 \
  python3 -I scripts/check_harmony_toolchain.py
systemd-run --user --scope \
  -p CPUQuota=200% -p MemoryHigh=5G -p MemoryMax=6G -p TasksMax=512 \
  python3 -I scripts/check_harmony_toolchain.py --native-test-target
systemd-run --user --scope \
  -p CPUQuota=200% -p MemoryHigh=5G -p MemoryMax=6G -p TasksMax=512 \
  python3 -I scripts/verify_harmony_composer.py \
  --target '<allocated target serial>' \
  --target-class emulator \
  --target-description '<target model, OS build and allocation identifier>' \
  --output '<new private evidence directory>'
```

The runner selects the checked-in `GeneratedComposer#committed_draft_focus_done_and_recreation` case through
`aa test -m entry_test -s unittest OpenHarmonyTestRunner -s class GeneratedComposer -s refractSuite GeneratedComposer`.
Public `aa test` has no `-a` option for choosing `ComposerTestAbility`; the default `TestAbility` therefore performs
this explicit suite/host dispatch. A mismatched selection or missing, failed, duplicate, incomplete or wrong-suite
record fails closed. The private report records source/tool/target/HAP identities and the observed case. Success
means only `native-committed-draft-executed-ime-unverified`: `imeVerified`, `renderVerified` and
`performanceMeasured` stay false. No settings-suite report may be substituted for this result.

The source-prepared Hypium/UI Test case exercises committed text injection, two distinct generated editors,
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
