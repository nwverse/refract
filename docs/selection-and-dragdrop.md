# Bounded text selection and typed drag/drop

This document specifies the typed contract for bounded text selection editing and typed drag/drop interop
on the Compose and ArkUI backends. It is the design companion to issue
[#206](https://github.com/nwverse/refract/issues/206).

## Scope and non-goals

In scope:

- **Bounded text selection editing** on a `TextField`, driven by a typed model action.
- **Typed drag source**: a view that publishes a typed `String` payload with a closed ASCII kind tag.
- **Typed drop target**: a view that accepts a `String` payload of a declared kind and forwards it to a
  typed model action, with empty-payload cancellation.

Explicit non-goals (out of scope, owned by other issues):

- **Rich-text selection ranges, link actions and AI-edit callbacks**: owned by
  [#201](https://github.com/nwverse/refract/issues/201). This document does not define those callbacks;
  a `textSelection` operation on a `TextField` is the bounded text-edit case only.
- **Arbitrary object or URI payloads**: rejected at parse time (`RFNATIVE005`). No `URI`, `Any`, `Data`,
  `content://` reference or runtime clipboard read is emitted.
- **Personal clipboard reads**: the payload of a drag source comes from app-owned state (`@State` String
  or a typed model property), never from `ClipboardManager`/`Pasteboard`.
- **Native gesture ownership**: the actual drag gesture, selection handles and IME behavior remain native;
  the generator does not reimplement them.

## Swift surface

The new operations extend the closed `NativeModifier.Operation` set (see `Sources/RefractIR/Interop.swift`):

```swift
// Bounded text selection editing on a TextField.
.textSelection(start: <Int>, end: <Int>, action: "replaceSelection")
//   Declares that the model exposes `func replaceSelection(start: Int, end: Int, replacement: String)`.
//   The native TextField invokes this after a selection edit. Cancellation (no edit) does not call it.

// Typed drag source.
.dragPayload(kind: "note", value: <String>)
//   `kind` is a lowercase ASCII identifier (letters/digits/underscore, starting with a letter).
//   `value` is a typed String expression owned by app state or a typed model property.

// Typed drop target.
.dropTarget(kind: "note", action: "receiveDrop")
//   Declares that the model exposes `func receiveDrop(kind: String, payload: String)`.
//   The native drop target invokes this only for a non-empty payload of the matching kind.
//   Empty payloads and foreign kinds are rejected by the generated wrapper without calling the action.
```

`kind` is a closed tag, not a free-form string: this prevents arbitrary MIME-type or URI schemes from
leaking into the generated code.

## Lowering

### Compose (`Sources/RefractCompose/ComposeNativeModifier.swift`)

- `textSelection` lowers to `TextField(value = TextFieldValue(text, selection = TextRange(start, end)))`
  whose `onValueChange` writes the new text into `@State` and calls the declared model action with the
  updated `selection.start`/`selection.end`.
- `dragPayload` lowers to `Modifier.dragAndDropSource { DragAndDropTransferData(ClipData.newPlainText(kind, value)) }`.
  `ClipData.newPlainText` is the Android SDK primitive for a plain-text clip; no URI is constructed.
- `dropTarget` lowers to `Modifier.dragAndDropTarget(...)` with a `remember`ed `DragAndDropTarget` whose
  `onDrop` rejects null and empty payloads and forwards a non-empty payload to the model action.
- The file is annotated `@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)` because
  the Compose drag-and-drop API is experimental. This is a real SDK call, not a runtime bridge.

### ArkUI (`Sources/RefractArkUI/ArkUIBackend.swift`)

- `textSelection` lowers to `TextInput({ text })` with `.onTextSelectionChange((start, end) => ...)` calling
  the declared model action with the current text.
- `dragPayload` lowers to `.draggable(true)` plus `.onDragStart((event) => event.setData({ [kind]: value }))`.
- `dropTarget` lowers to `.allowDrop([{ type: kind }])` plus `.onDrop` that gates on `payload.length > 0`.

## Ownership rules

- **App owns the model**: the action name in `action:` must resolve to a method on a `RefractModel` protocol
  declared in the same source module. The generator checks this at emit time (`RFNATIVE005`).
- **App owns the payload value**: `dragPayload.value` must be a typed `String` expression; the generator
  refuses to call `ClipboardManager`, `Pasteboard`, or any system clipboard API.
- **Native gesture ownership**: drag start, drag end, drop detection, selection handles and IME behavior
  are the platform toolkit's. The generated code only supplies the typed payload and the callback.
- **Cancellation**: a cancelled drag (no drop event) calls nothing; a drop with an empty payload is gated
  in the generated wrapper before the model action is invoked. The model never sees empty payloads.

## Evidence

- **Golden fixtures** (`Fixtures/selection-dragdrop/`): a single Swift input that uses all three operations,
  with the generated Kotlin and ArkTS committed and diffed by the golden test runner.
- **Rejected fixture** (`Fixtures/selection-reject-uri-payload/`): a non-`String` payload (an `Int` literal
  standing in for an arbitrary object) is rejected at parse time with `RFNATIVE005`.
- **Frontend unit tests** (`Tests/RefractFrontendTests/SelectionDragDropTests.swift`): 11 tests covering
  typed payload acceptance, kind-identifier validation, undeclared-action rejection, receiver-type
  validation, and Unicode payload round-trips.
- **Android Kotlin compilation**: `Fixtures/selection-dragdrop/Expected.kt` is staged by
  `scripts/check_fixture_compilation.py` and compiled by `./gradlew :fixtures:compileDebugKotlin`
  in `examples/android/`. This is a compile-only gate; no emulator or device is involved.
- **Native JVM unit tests** (`examples/android/fixtures/src/test/java/com/example/refract/selection/DropTargetContractTest.kt`):
  7 JUnit tests drive the same gating logic the generated Kotlin emits, covering empty payload
  cancellation, null payload cancellation, non-BMP emoji round-trip, CJK round-trip, mixed unicode
  round-trip, and the whitespace-only boundary. Evidence level: source / Native JVM (plain JVM, not
  Robolectric, not an emulator, not a device).

## Relationship to other issues

- **#201 (rich text selection, links, AI-edit)**: out of scope here. `textSelection` on a `TextField`
  handles bounded text edits only; rich-text ranges, link taps and AI-edit hand-off are #201's contract.
- **#205 (focus, keyboard, IME)**: orthogonal. Selection handles and IME behavior stay native; this issue
  does not redefine focus or keyboard ownership.

## Verification limits

- The generated Kotlin compiles against `androidx.compose.foundation:foundation` via the standard BOM
  pinned in `examples/android/fixtures/build.gradle.kts`. Compose drag-and-drop is experimental; the
  `@OptIn` annotation makes that explicit at the file level.
- The generated ArkTS uses `onTextSelectionChange` (API 12+) and `onDragStart`/`onDrop`. The HarmonyOS
  toolchain is not installed on the verification machine, so ArkTS compilation is **not verified**;
  the ArkTS output is reviewed as source against the documented API surface.
- No emulator, device or simulator is used; native evidence is source-level Kotlin compilation plus
  Native JVM unit tests of the gating logic.
