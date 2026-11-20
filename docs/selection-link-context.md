# Typed selection, link activation and explicit context actions

This is the bounded #201 contract for literal rich text hosted by an app-owned native view. It does not render
Markdown, project changing message blocks, open URLs or implement a selection/IME engine.

## Swift contract

The ordinary Swift source declares immutable `RefractSelectionRange`, `RefractSelectionLink`,
`RefractSelectionContent` and `RefractSelectionContext` values. A `RefractNativeView` accepts literal content,
`(String) -> Void` link activation and `(RefractSelectionContext) -> Void` explicit context actions. These are
closed native-only types; they are not general Screen inputs, state, bindings or arbitrary model objects.

```swift
protocol SelectionMessageModel: RefractModel {
    func openLink(_ destination: String)
    func useAsContext(start: Int, end: Int, text: String)
    func editWithAI(start: Int, end: Int, text: String)
}

NativeSelectionMessage(
    content: RefractSelectionContent(text: "读 🌸 docs", links: [
        RefractSelectionLink(range: RefractSelectionRange(start: 5, end: 9),
                             destination: "https://example.test/docs"),
    ]),
    onLink: { destination in model.openLink(destination) },
    onUseAsContext: { context in
        model.useAsContext(start: context.range.start, end: context.range.end, text: context.text)
    },
    onEditWithAI: { context in
        model.editWithAI(start: context.range.start, end: context.range.end, text: context.text)
    }
)
```

A Screen still has only `let model: SelectionMessageModel`. The new closure forms belong to the native host call;
the generator resolves their single body against a declared `RefractModel` action. The native declaration must
contain exactly `content`, `onLink`, `onUseAsContext` and `onEditWithAI`, with the source types above, in that
order. A partial, renamed, reordered or extended declaration, or use of `(String) -> Void` on an unrelated native
component, is an `RFNATIVE001` build-time diagnostic. Neither backend emits output for that declaration.
Arbitrary closures, captured values, snapshot rewriting and unrelated method signatures are rejected. No second
callback ABI is introduced:
`NativeArgument` carries the closed literal content or the already-resolved model action.

The `ModelParameter` scalar boundary cannot directly represent `RefractSelectionContext`, so this implementation
keeps the existing `(start: Int, end: Int, text: String)` model methods. The native host constructs the immutable
context value and the generated adapter forwards its three fields. `selectionContent` and
`selectionContextAction` are closed additions to the existing `NativeParameterType`/`NativeArgument` channel, not
an independent IR family or runtime payload interpreter.

## Ranges and actions

Offsets are UTF-16 code units on every platform. Empty selection (`start == end`) is valid for explicit context
and AI-edit snapshots. `0 <= start <= end <= text.utf16.count` must hold, and neither boundary may split an emoji
surrogate pair. Link ranges must be nonempty, ordered and disjoint. Invalid offsets, overlapping links, dynamic
ranges and nonliteral destinations are diagnostics (`RFSELECTION001`–`RFSELECTION004`).

Only literal absolute HTTPS destinations with a nonempty host are accepted. Activation calls the model with the
unchanged destination String; generated code never opens a URL or implements the separate destination-policy and
native-handoff work. Selection movement alone invokes neither context action. A native explicit Use-as-context or
AI-edit action captures the current text/range as one immutable snapshot.

The app owns selection handles, gestures, focus, IME/composition and the iOS/Android/HarmonyOS presentation. The
Compose host keeps its selection state native and constructs immutable Kotlin values. ArkTS uses explicitly
mapped immutable native value classes. No singleton, runtime view registry, hidden XML/HTML or projected-message
range translation is generated. Dynamic projected message content is rejected until a separate typed adapter can
preserve live revisions and range ownership.

## Evidence and limits

- `Fixtures/selection-link-context/` is the canonical literal Unicode/link source, with real CLI-generated Kotlin
  and ArkTS. `Fixtures/selection-link-context-reject/` rejects a range that splits an emoji surrogate pair.
- `SelectionLinkContextTests` verifies model callback resolution, dual-backend lowering, empty/Unicode metadata,
  invalid bounds, overlapping ranges, non-HTTPS destinations, arbitrary callbacks and projected-content rejection.
  Its declaration tests also reject eight partial, renamed, reordered or extended literal-selection host signatures.
- `examples/android/fixtures` compiles the generated Kotlin and runs plain Native JVM host tests for empty and
  Unicode snapshots, movement without callbacks, separate explicit actions, link delegation and invalid ranges.
  These tests do not use an emulator, device, IME, clipboard or actual URL opener.
- The shared source is also the iOS source contract: native SwiftUI selection and explicit buttons call the
  injected host callbacks. Actual Xcode/iOS compilation and gesture behavior require separate platform evidence.
  ArkTS output and its app-owned value declarations are source-only until a real HarmonyOS compiler runs.
