# Native text input: focus, keyboard, IME and draft ownership

`RefractTextInputHost` is a deliberately narrow native-component boundary for text input that must preserve native
focus, keyboard and IME behavior. It does **not** extend ordinary generated `TextField`, and it does not claim that
`@FocusState`, a `String` binding or a generated Compose/ArkUI text control proves Android or HarmonyOS IME semantics.

The accepted fixture is `Fixtures/interop-text-input-host/`. Both backends emit a direct call to the application's
`NativeTextInputHost`; there is no Refract runtime, registry, input-method interpreter or target-code template.

## Source and typed call contract

`RefractTextInputHost` is an ordinary SwiftUI `View` on iOS. Its declaration has exactly four public inputs plus private native
focus state:

```swift
struct NativeTextInputHost: RefractTextInputHost {
    @Binding var draft: String
    let focusRequest: Int
    let onDraftCommit: (String) -> Void
    let onCommit: () -> Void

    @FocusState private var isHostFocused: Bool

    var body: some View {
        TextField("Message", text: $draft)
            .focused($isHostFocused)
            .submitLabel(.done)
            .onChange(of: focusRequest) { _, _ in isHostFocused = true }
            .onSubmit {
                onDraftCommit(draft)
                onCommit()
            }
    }
}
```

A consuming generated screen passes two parent-owned bindings and two typed model actions:

```swift
NativeTextInputHost(
    draft: $draft,
    focusRequest: focusRequest,
    onDraftCommit: { value in model.commitDraft(value) },
    onCommit: { model.commit() }
)
```

`focusRequest` is a monotonically increasing request token, not a mirrored Boolean that can become stale. A new token
requests focus and the soft keyboard; it does not force focus loss or reset the draft. `onDraftCommit` publishes a
committed native editor value for application submission. `onCommit` performs the app's explicit return-key action.
The parent also owns ongoing committed-draft updates through the ordinary binding callback. Arbitrary closures,
local-only draft storage, missing native focus state, other action shapes, additional host ABI fields and use of the
marker with a different component name are diagnostics. The host's committed-draft callback has its exact dedicated
ABI; it is not the separate `docs/selection-link-context.md` typed destination callback, even though both use a
String payload. The host validator does not silently give arbitrary native components its draft-editing semantics.

`docs/interop.md` owns the generic typed mapping representation. `action` and `actionString` are signatures, not
arbitrary executable mapping strings. The source declaration's stored properties retain their bounded payload types;
the specialized host validator pairs the last two with these exact callback shapes. The generated Compose entry point receives `draft`, `onDraftChange`,
`focusRequest`, `onFocusRequestChange` and the generated model interface. ArkUI receives the corresponding
`@Param`/`@Event` values and a typed host call. No focus or composition object crosses either entry point.

## Ownership during editing

| State or action | Owner | Cross-platform behavior |
| --- | --- | --- |
| Committed editable draft | Application/parent | `String` binding; updated after a native commit/edit operation |
| Native preedit/composing span | Platform editor/input connection | Never copied into a shared `String` binding |
| Selection, composing cursor and candidate choice | Platform editor/IME | Not serialized or synthesized by Refract |
| Focus request | Application plus native host | Incrementing token triggers native focus/keyboard request |
| Return key | Native editor | `done` finishes native composition before explicit app commit |
| Submission and draft persistence | Application model | Typed callbacks; no generated storage, process-restoration adapter or global draft |

The application must retain its committed draft across the screen's ordinary recomposition/re-render and any desired
navigation or process-restoration lifecycle. Refract does not generate persistence. An external parent edit must not
replace an active native preedit. Native text replacement is allowed when no composition is active.

## Android implementation and evidence

The app-owned implementation is
`examples/android/app/src/main/java/com/example/refract/input/NativeTextInputHost.kt`. `AndroidView` hosts a real
`EditText`, not Compose `TextField`'s `String` overload. Its `BaseInputConnection` distinguishes `setComposingText`
from `commitText` synchronously; a `TextWatcher` alone is not treated as a reliable discriminator across IMEs.

- `setComposingText` retains the platform's composing span and does not notify the shared draft.
- `commitText` finishes that composition state and publishes the resulting committed text through `onDraftChange`.
- `IME_ACTION_DONE` and the hardware Enter path finish native composition, publish the actual editor contents through
  `onDraftCommit`, clear focus, request keyboard dismissal, then invoke `onCommit`.
- Focus loss finishes native composition without erasing the committed draft or changing the selection. Native
  selection remains in the `EditText`; it is not reconstructed from a shared string.
- Recomposition and external draft changes do not overwrite a live composing span. Callback references use native
  `State` so callbacks do not capture stale model values.

Finishing composition is **not** a pinyin-to-Hanzi translation algorithm. The host never invents a Chinese candidate.
A real IME may finish its own composing text into the editor before a done action; the host then publishes that actual
committed native content. Candidate selection, exact keyboard-window behavior and third-party IME differences require
an Android emulator or physical-device test with the chosen IME.

The fixture test invokes the exact generated `ComposerScreen`, compiles it against this native host and drives its real
`EditText`/`InputConnection`. The app-owned optional `CompositionLocal` observer lets tests inspect the editor without
adding a test-only generated parameter. It defaults to absent and is not a Refract runtime or generated dependency.
Tests cover Chinese commit, uncommitted pinyin isolation, recomposition and external updates during preedit, Unicode
selection, focus restoration, done and Enter ordering, draft commit and keyboard dismissal.

These are **Native JVM / Robolectric** results on the pinned Android API test runtime, not Android emulator or device
results. They establish real Android host code behavior under that runtime, not third-party Chinese-IME compatibility,
real window-manager behavior or device performance.

## iOS and HarmonyOS boundaries

The iOS body above uses SwiftUI's native `TextField`, `@FocusState`, `.submitLabel(.done)` and `.onSubmit`. SwiftUI owns
its marked text and IME interaction; no composition is read, reconstructed or synthesized by this source. The example
prelude declares `RefractTextInputHost: View` with no runtime implementation. The uniquely named
`examples/shared/InteropTextInputHost.swift` is byte-identical to the canonical fixture and is compiled by the example
Xcode project, so the macOS CI job can type-check the exact host body rather than only parse it with SwiftSyntax.
Linux Swift tests cannot type-check SwiftUI. macOS/Xcode compilation is CI evidence, while iOS simulator/device
editing remains a separate runtime check; neither is inferred from the frontend accepting this source.

HarmonyOS receives a direct `NativeTextInputHost` object call with the committed draft, draft-change callback, focus
request and typed commit callbacks. The app-owned implementation is
`examples/harmony/entry/src/main/ets/native/NativeTextInputHost.ets`, byte-identical to
`Fixtures/interop-text-input-host/NativeTextInputHost.ets`. The native test ability imports the unchanged CLI-generated
`examples/harmony/entry/src/main/ets/generated/InteropTextInputHost.ets` (the canonical output apart from its
source-name header), so no hand-written substitute screen or runtime adapter sits between the generated call and this
host. The example generation transaction also emits the corresponding Kotlin call against the existing Android host;
this slice changes no Android implementation or behavior.

**The implementation is source-prepared only, not compiled or executed.** It selects APIs from the public
[TextInput reference](https://gitee.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-textinput.md)
and [shared text types](https://gitee.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-text-common.md).
Those references are not evidence that the selected vendor compiler accepts the source or that a real IME follows the
same event sequence. The API 12+ `EditableTextOnChangeCallback` preview argument and API 18+ two-argument
`OnSubmitCallback` require the chosen API 26 SDK; compilation must verify their exact ArkTS signatures before use.

The host implements the bounded behavior as follows:

- `TextInput` owns its `PreviewText`, selection and IME interaction. `onChange(value, previewText)` publishes neither
  `value` nor the preview while nonempty preview text is active; the host keeps only a Boolean `previewActive` gate,
  not a composition string. Publication additionally requires a mounted native editing session. `onEditChange(false)`
  invalidates that session and cached preview without publishing it, while `aboutToDisappear` marks the host unmounted
  so delayed edit callbacks cannot publish stale text or enable Done. A new mount initializes a fresh session.
- If the parent draft changes during preview, its new value is retained in the parent/editor rather than silently
  discarded. The host ends the old native editing session, displays an explicit uncommitted-preview diagnostic and
  rejects any delayed callback from that session. It does not cache preview for restoration or choose a candidate.
  A subsequent user focus request and fresh native editing session are required before further committed edits.
- Each increased focus token calls the native `FocusController.requestFocus` followed by the public foreground-app
  `inputMethod.getController().showTextInput()` request. The target is derived from API 12+
  `this.getUniqueId()`, not a constant shared by multiple host instances. Focus alone is not presented as keyboard
  evidence. Either failure becomes a visible native diagnostic; no system-application-only keyboard permission is
  requested. Ordinary focus loss does not reset the committed draft or reconstruct selection, and a later token
  restores native focus without copying a preedit into the parent.
- A Done callback outside a mounted native editing session or with active preview does **not** clear the preview,
  select a candidate, clear focus or call the application's commit actions. It displays an explicit
  candidate/session diagnostic and calls `keepEditableState()` so the user can choose through the real IME. This is an
  intentional unsupported-operation diagnostic, not a fabricated commit.
- Once the mounted session is actively editing with no preview, submit invalidates that session, calls `stopEditing()`,
  publishes `SubmitEvent.text` rather than the possibly stale parent binding, invokes `onDraftCommit`, publishes that
  same ongoing committed draft, clears native focus and then invokes `onCommit`. The binding callback is unconditional
  during submit so it cannot be skipped because a parent update is still pending. `stopEditing()` is the documented
  native edit/keyboard exit; it is not treated as a general operation for committing an active IME candidate.
  `clearPreviewText()` is deliberately never used as a substitute.
- The application owns the retained draft and submitted value. The separate
  `examples/harmony/entry/src/ohosTest/ets/testability/GeneratedComposerHost.ets` mounts two actual generated children
  with independent drafts/focus tokens, recreates one in separate UI actions and explicitly transfers focus to another
  native control. Hypium/UI Test source in `GeneratedComposer.test.ets` compares distinct editor IDs, asserts focus
  transfer/restoration and covers committed text, hardware Enter, recreation and callback state. These tests remain
  source-prepared; `inputText()` is not preedit or candidate evidence.

The exact remaining gate is an authorized matching DevEco CLI/SDK compile of the application and `entry@ohosTest`,
followed by an owned signed simulator/device run. A native tester must select a named real Chinese IME, create visible
preview text, change the parent during preview and verify the explicit session-ending diagnostic, retained parent value
and rejection of delayed old-session callbacks. With an unchanged parent, choose a candidate in that IME and verify
that only the chosen committed value reaches the draft. Exercise focus loss/restoration plus both software Done and
hardware Enter, with the two mounted editors demonstrating distinct focus targets. Record the actual
preedit-to-commit transition, native callback order and keyboard dismissal. An active-preview or stale-session Done
must show the native diagnostic without invoking either commit callback; a subsequent real candidate selection in a
fresh active session followed by Done must publish exactly once. If the chosen SDK/IME does not supply the preview or
editing-state transitions assumed above, stop and revise the host against compiler/runtime evidence rather than
adding a composition mirror or synthetic candidate.

Portable checks:

```sh
python3 -I scripts/check_harmony_text_input.py
python3 -I scripts/test/test_harmony_text_input.py
python3 scripts/check_examples.py
python3 scripts/check_harmony_toolchain.py --check-only
```

The first two are source-contract checks with negative mutations, not ArkTS parsing, compilation or runtime tests.
`check_examples.py` regenerates the exact shared Swift source through the same CLI transaction as the other example
screens and diffs both native outputs. This preserves the existing Android host implementation without modifying its
native code or changing its behavior. The CI `refract check` includes this same input over both committed output roots,
so an added generated host cannot be rejected as unexpected. `scripts/test_example_output_transaction.py --self-test`
runs that exact workflow command and its missing-input/missing-output negative cases. The final preflight currently
exits 2 because the authorized tools are absent. Signing, `hdc`, simulator/device execution and
Chinese-IME compatibility therefore remain unexecuted; this preparation slice does not close #245.

## Diagnostics and verification levels

| Code | Meaning |
| --- | --- |
| `RFINPUT001` | The specialized host declaration is missing, incomplete or has a wrong native focus/input ABI. |
| `RFINPUT002` | A host argument is not the required parent binding or typed model callback. |
| `RFINPUT003` | The source/native mapping is not the bounded host ABI, or callbacks are added to an ordinary native component. |

Use these evidence labels exactly:

1. **Source/golden:** the actual CLI emits and diffs Kotlin and ArkTS.
2. **Kotlin compilation:** the staged generated Kotlin and app-owned Android implementation compile with Gradle/JDK 21.
3. **Native JVM:** Robolectric executes the real generated call, Android `EditText` and `InputConnection` tests.
4. **Simulator/emulator/device:** not supplied by this change; none of the preceding evidence substitutes for it.
5. **iOS/macOS and HarmonyOS:** their own compiler/runtime boundaries remain explicit until exercised with those tools.
