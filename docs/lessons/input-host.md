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

## ArkUI preview and submit are not Android InputConnection operations

ArkUI `TextInput` reports native preview through the optional `PreviewText` argument of `onChange`; do not publish its
`value` as a committed binding while that preview is nonempty. `TextInputController.clearPreviewText()` clears preview;
it does not select or commit the IME's candidate. If a public commit-preview operation is unavailable, an active-preview
Done must retain editing and produce an explicit diagnostic, not clear preview or fabricate Chinese text. Once no
preview is active, use `SubmitEvent.text`, not a possibly stale parent binding. Keep focus/keyboard requests and their
error callbacks native: `FocusController.requestFocus` alone does not prove a visible keyboard, and the public
`showTextInput()` request still needs authorized compiler and real-IME verification.

## Do not race fixture staging with Kotlin compilation

The fixture staging script cleans and repopulates its ignored Kotlin source directory. Never launch it in parallel
with Gradle: the compiler can observe a partial source set and report missing generated files. Finish staging, then
run compilation and Native JVM tests sequentially. Set `REFRACT_CLI_PATH` explicitly for the app's opt-in Gradle
source-generation task; a successful `:fixtures` build does not configure that application task.
