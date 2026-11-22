# Input host pitfalls

## A native marker's iOS body is not a second generated child View

A specialized `RefractTextInputHost` declaration needs the same marker treatment as `RefractNativeView`: its body stays
ordinary SwiftUI on iOS, while its calls go through the specialized argument parser. Do not add every marker to the
child-View declaration registry or let the general View visitor translate its body. That changes existing native
components and can drop specialized callback arguments. Keep the specialized kind in the IR and dispatch on that kind
at both frontend and backend boundaries.

## Action types are not scalar value types

`action` and `actionString` describe callback shapes. They cannot be decoded by `ValueType(rawValue:)`, and an Optional
`flatMap` cannot flatten a `ValueType?` returned by that failable initializer. Validate callback shape separately from
its payload type. Generic scalar interop must remain unchanged; do not give every `RefractNativeView` an arbitrary
String-consuming closure ABI just to support one bounded host. A separately supported generic no-argument model action
keeps its own typed `StateAction` path and is not the host's String callback.

## Compose text callbacks do not establish IME ownership

A `String` `TextField` callback and a shared `@FocusState` declaration do not prove that Android preedit is preserved.
An app-owned Android `EditText`/`InputConnection` can distinguish `setComposingText` from `commitText`; the composing
span and candidate choice belong to that native editor and the IME. Do not publish uncommitted pinyin into the shared
draft, translate it to Chinese, or replace an active composing span during recomposition.

`finishComposingText` ends a composing region; it is not a pinyin-to-Hanzi conversion. A done action publishes the
actual native editor content after finishing composition. Test that behavior directly with `InputConnection`, and
label Robolectric as Native JVM rather than an emulator/device or third-party IME result.

`BaseInputConnection.sendKeyEvent` dispatches an IME's hardware event back through the target View. If the custom
`EditText.onKeyDown` owns Enter submission, do not submit again from the connection's matching key-up. Cover both
boundaries and drain the native dispatcher in the regression test; a direct View-only call cannot expose duplicate
`onDraftCommit`/`onCommit` callbacks.

## ArkUI preview and submit are not Android InputConnection operations

ArkUI `TextInput` reports native preview through the optional `PreviewText` argument of `onChange`; do not publish its
`value` as a committed binding while that preview is nonempty. `TextInputController.clearPreviewText()` clears preview;
it does not select or commit the IME's candidate. If a public commit-preview operation is unavailable, an active-preview
Done must retain editing and produce an explicit diagnostic, not clear preview or fabricate Chinese text. Once no
preview is active, use `SubmitEvent.text`, not a possibly stale parent binding. Keep focus/keyboard requests and their
error callbacks native: `FocusController.requestFocus` alone does not prove a visible keyboard, and the public
`showTextInput()` request still needs authorized compiler and real-IME verification.

Scope preview publication to a mounted native editing session: editing loss and disappearance invalidate the gate, and
late callbacks cannot publish. A parent edit during preview must not be silently discarded; retain the parent value,
end the old session explicitly and reject its delayed callbacks. Use the custom component's `getUniqueId()` for each
native focus target. Source checks must inspect guarded control flow, not only the textual order of commit calls.

## Real IME automation must not inject the behavior it claims to verify

A UIAutomator test is not real-IME evidence merely because it runs in an instrumentation APK. Click the actual IME's
letter keys, candidate and Done control; read the editor and composing span only for observation. Never replace an
unavailable keyboard/candidate with `InputConnection`, editor `setText`, paste, key injection or `adb shell input text`.
Require the exact enabled/default IME package, service, installed version and selected Chinese subtype before starting.
A test app reading that package metadata on Android 11+ needs the bounded `android.view.InputMethod` `<queries>`
declaration; package visibility is separate from permission to configure an IME.
Fail closed on missing arguments, ambiguous key/candidate controls or an invisible keyboard. Test activity recomposition
can be driven natively without touching the editor; do not click an unrelated control during live preedit if that would
finish composition. `InputMethodInfo` exposes `subtypeCount`/`getSubtypeAt`, not Kotlin's `subtypeList`.

Compiling this harness and staging the exact generated host are preparation evidence, not emulator/device acceptance.
Retain the target class, OS build, IME version/subtype and connected-test output only after the real run.

## Do not race fixture staging with Kotlin compilation

The fixture staging script cleans and repopulates its ignored Kotlin source directory. Never launch it in parallel
with Gradle: the compiler can observe a partial source set and report missing generated files. Finish staging, then
run compilation and Native JVM tests sequentially. Set `REFRACT_CLI_PATH` explicitly for the app's opt-in Gradle
source-generation task; a successful `:fixtures` build does not configure that application task.
