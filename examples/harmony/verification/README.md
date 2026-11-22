# Generated settings native rendering verification

## Current status: source-prepared, not executed

The real CLI-generated `SettingsScreen` has **not** been compiled or rendered. No authorized HarmonyOS compiler,
SDK, signing configuration, `hdc` or owned execution target is available to this checkout. The documented preflight
reports that blocker; this page does not turn source review into compile, rendering, accessibility-service or device
evidence. The rendering gate in [issue #166](https://github.com/nwverse/refract/issues/166) remains open until the
steps below run and their captures are inspected.

The test-only `TestAbility` loads `GeneratedSettingsHost`, a small ordinary ArkUI `@Entry` component that calls the
unchanged generated `SettingsScreen` with a native `@ObservedV2` model and parent-owned binding. It does not replace
or fork the generated component. The application example's existing mixed-code route is unchanged. No Refract
library, runtime registry, performance probe or test code is part of the application source set.

## What the native checks cover

`GeneratedSettingsRender.test.ets` uses Hypium and the platform's UI Test APIs to:

- find the real Profile, Preferences, Notifications and Save content and verify enabled native controls;
- require a checkable/clickable `Toggle` in its off state, inspect its native semantics through the UI Test component
  tree, check its alignment with the Notifications label and exercise off → on → off binding;
- change the native model through the host's own button, enter text into the actual `TextInput`, scroll the actual
  `List` to Save and verify the native save callback;
- capture light and dark full-screen PNGs and API 26 native layout JSON. A missing control, failed action, unsupported
  layout dump or missing capture fails the test; nothing is silently skipped.

UI Test queries use accessibility nodes. This verifies the inspected native attributes used by the test, not a
screen-reader traversal, contrast audit, large-text behavior or full accessibility certification. Those remain
separate acceptance work. No timings, memory figures, paired native comparison or performance claim is collected;
issue #167 owns that independent benchmark path.

## Authorized prerequisites

Follow [the toolchain guide](../../../docs/harmony-toolchain.md). A developer must personally obtain and authorize
the matching Command Line Tools 26.0.0/SDK, dependencies and official signing workflow. Allocate an emulator or
physical device before starting; this repository does not create, boot, reset or implicitly select a shared target.
Keep its serial, signing material, machine paths and captures outside the repository. Never commit credentials or
license-authorized installation data.

Regenerate the examples first and compile the actual generated source plus native tests:

```sh
swift build
python3 scripts/check_examples.py
python3 scripts/check_harmony_toolchain.py --check-only
python3 scripts/check_harmony_toolchain.py
python3 scripts/check_harmony_toolchain.py --native-test-target
```

The `ohosTest` module's `test_pages.json` registers its native host. Its own theme buttons change the application
color mode in the same session, avoiding an assumption that the test ability will be recreated. The native checks
also scroll back to the model/save observation before capturing the final light image. Do not substitute the normal
application ability for this target. The runner passes `refractSuite=GeneratedSettingsRender` through the public
`AbilityDelegatorArgs.parameters` dictionary, so `TestAbility` registers only that suite and its matching host.
An unsupported selection throws instead of silently running another suite.
The UI Test API contracts used here are the public
[UI Test guide](https://github.com/openharmony/docs/blob/master/en/application-dev/application-test/uitest-guidelines.md),
[UI Test API reference](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-test-kit/js-apis-uitest.md)
and [Hypium result protocol](https://github.com/openharmony/docs/blob/master/en/application-dev/application-test/unittest-guidelines.md),
plus [delegated test arguments](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-test-kit/js-apis-inner-application-abilityDelegatorArgs.md).
They are documentation references, not evidence that these sources passed the selected vendor compiler.

## Reproduce on an explicitly owned target

After authorizing the toolchain, signing and target for the same source revision, run from a clean repository root:

```sh
python3 scripts/verify_harmony_settings.py \
  --target '<allocated target serial>' \
  --target-class emulator \
  --target-description '<target model, OS build and allocation identifier>' \
  --output '<new private evidence directory>'
```

Use `--target-class device` only for an actual physical device. The runner rejects a nonempty checkout and missing
vendor prerequisites, records the full source revision and tool version, compiles both targets, and installs private
snapshots of the canonical signed app and test outputs from those exact builds. It preserves vendor output and commands
in the private log. Old canonical outputs are quarantined before building so a no-op build cannot inherit them; they
are restored on failure, and a restoration conflict preserves rather than deletes the old files. Explicit `--app-hap`
or `--test-hap` paths are permitted only when their bytes match the corresponding snapshot immediately before each
installation. Missing, mismatched or replaced inputs fail closed; installation opens the private snapshot, never the
mutable selected path. Previously built or external HAPs do not bypass the native build or establish their own
provenance.

The runner parses the pinned suite/case/task lifecycle in order: the selected `GeneratedSettingsRender` suite start,
exactly its two named cases with start and successful completion records, suite end, one complete summary, exactly one
zero terminal record and task completion. Package-level `numtests` may include the separately filtered contract test;
it is not the selected suite count. Missing, duplicate, wrong, failed, reordered or mixed terminal records fail closed.
It retrieves the fixed PNG/layout manifest after the complete interaction sequence, including the return from the
scrolled position. Invalid/missing files fail closed. It never reports `renderVerified: true`: successful execution
ends as `executed-awaiting-human-capture-inspection`.

Finally, open all light/dark PNGs and layout JSON files. Inspect the actual labels, input, switch, Save control,
scrolled content, backgrounds and native attributes. Record the reviewer, inspected source/tool/target metadata and
observations in the issue, retaining private captures where device information must not be public. Execution without
this inspection is not a completed rendering gate. Physical-device rendering is still required even if an emulator
run passes; an emulator result must never be relabelled as device evidence.

## Portable checks available without the SDK

The separate [committed-draft text-input guide](text-input.md) adds its own source-only host checks. It shares this
page's missing authorized compiler/signing/target blocker and is not a native IME or device result.

```sh
python3 -I scripts/test/test_harmony_toolchain.py
python3 -I scripts/test/test_harmony_render.py
python3 -I scripts/check_harmony_text_input.py
python3 -I scripts/test/test_harmony_text_input.py
python3 -I scripts/check_harmony_toolchain.py --check-only
```

The tests validate the host wiring and fail-closed evidence logic. They use no fake SDK, compiler, `hdc`, screenshot
or render result. The final preflight command currently exits 2 when the authorized tools are absent; that is the
expected blocker, not a passing native test.
