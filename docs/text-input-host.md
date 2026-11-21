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

The separate `examples/android/ime-verification/` test application supplies the fail-closed UIAutomator harness for the
Android slice of #245; its preparation subtask is #286. It compiles the same CLI-staged generated host, requires the
target owner's exact authorized IME component/version and selected Chinese subtype, and clicks only actual keyboard
keys, the named candidate and Done. It fails on missing prerequisites rather than injecting composition or text. The
harness covers preedit isolation, candidate commit, recomposition, focus restoration, Done order, keyboard dismissal
and parent-owned draft retention across view recreation. **It is preparation and Kotlin-compilation evidence only until
its connected test passes on a named target with a named IME.** No such target or real-IME result is supplied here.

## iOS and HarmonyOS boundaries

The iOS body above uses SwiftUI's native `TextField`, `@FocusState`, `.submitLabel(.done)` and `.onSubmit`. SwiftUI owns
its marked text and IME interaction; no composition is read, reconstructed or synthesized by this source. The example
prelude declares `RefractTextInputHost: View` with no runtime implementation. The uniquely named
`examples/shared/InteropTextInputHost.swift` is byte-identical to the canonical fixture and is compiled by the example
Xcode project, so the macOS CI job can type-check the exact host body rather than only parse it with SwiftSyntax.
Linux Swift tests cannot type-check SwiftUI. macOS/Xcode compilation is CI evidence, while iOS simulator/device
editing remains a separate runtime check; neither is inferred from the frontend accepting this source.

HarmonyOS receives a direct `NativeTextInputHost` object call with the committed draft, draft-change callback, focus
request and typed commit callbacks. Its application component must own `TextInputController`, native focus, keyboard
dismissal and native composition/editing behavior. The following is a required app-owned contract sketch, not a
compiled implementation or evidence that a particular HarmonyOS release exposes every shown spelling:

```typescript
@ComponentV2
export struct NativeTextInputHost {
  @Require @Param draft: string;
  @Event onDraftChange: (value: string) => void = (value: string): void => {};
  @Require @Param focusRequest: number;
  @Event onDraftCommit: (value: string) => void = (value: string): void => {};
  @Event onCommit: () => void = (): void => {};
  private controller: TextInputController = new TextInputController();
  private lastFocusRequest: number = 0;

  aboutToAppear(): void {
    this.lastFocusRequest = this.focusRequest;
  }

  build() {
    TextInput({ text: this.draft, controller: this.controller })
      .onChange((value: string) => {
        // Verify against the native SDK that this is a committed edit, never
        // an intermediate IME composition preview, before publishing it.
        this.onDraftChange(value);
      })
      .onSubmit((enterKey: EnterKeyType) => {
        // Finish native editing through the actual SDK/IME, then publish the
        // editor's committed value. Never construct Chinese from a pinyin key.
        this.controller.stopEditing();
        this.onDraftCommit(this.draft);
        this.onCommit();
      })
  }
}
```

The concrete focus-token observation and exact `stopEditing`/submit behavior must be implemented and compiled against
the chosen SDK. Do not copy this sketch into an app without that verification. The source-level host ABI deliberately
omits native selection/composition objects, so none of these controls becomes a generated runtime adapter. A composed
value must not be mirrored into a separate generated
composition string. Submit must finish/commit native editing before the app callback, and losing focus must preserve
the committed draft. The mapping checks this host ABI at generation time; it does not prove an ArkUI SDK API.

There is no HarmonyOS command-line toolchain or runtime available in the current environment. The ArkTS fixture is
therefore source-generation evidence only: it is not compiled ArkTS, a simulator run, a device IME test or a claim
that an as-yet unprovided application host implements every native behavior. Actual ArkTS compilation and native
Chinese editing need the authorized HarmonyOS toolchain and a suitable simulator/device.

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
