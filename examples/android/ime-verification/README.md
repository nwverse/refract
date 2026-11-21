# Android real-IME host verification

This directory is a separate test application for the Android slice of #245. It is **preparation only**: the current
Linux environment has no attached Android target, no target allocated to this work, and no `/dev/kvm`. No real-IME test
has run and no Android emulator/device, third-party-IME compatibility or performance acceptance is claimed.

The application calls the exact CLI-staged `refract.generated.ComposerScreen` from `Fixtures/interop-text-input-host/`
through the existing `:fixtures` module. It uses the unchanged app-owned `NativeTextInputHost`; neither generated code
nor the native host is copied here. The test-only activity supplies parent-owned draft state, a second native field,
focus-request and host-removal controls, and read-only event observation. It adds no production application dependency,
runtime, registry or composition mirror.

## Fail-closed input boundary

`RealChineseImeInstrumentedTest` requires all of the following instrumentation arguments:

| Argument | Required target-owner input |
| --- | --- |
| `requiredIme` | Flattened package/service component of the authorized, already installed Chinese IME |
| `requiredImeVersion` | Exact installed IME `versionName` |
| `requiredImeLocale` | Exact selected subtype locale, for example `zh_CN` |
| `requiredImeMode` | Exact selected Pinyin subtype mode reported by Android |
| `requiredTarget` | Target owner's public name for the allocated emulator/device; do not include a private host name |
| `requiredHostClass` | Exactly `emulator` or `device`, as independently confirmed by the target owner |
| `requiredCandidate` | One visible Han candidate produced by real `n`/`i` Pinyin key presses, for example `你` |
| `imeKeyResourcePrefix` | Optional full resource-ID prefix for letter keys; otherwise one unambiguous visible key text/content description is required |
| `imeDoneResourceId` | Optional full resource ID of the real Done control when its text/content description is ambiguous |

The test reads Android's default/enabled IME settings, installed package version, input-method service permission and
current subtype. It fails instead of skipping or choosing a fallback when these do not match. It also fails when the
IME window, one real `n`/`i` key, the named candidate, or one unambiguous Done control is unavailable. A resource
prefix or keyboard layout is never used to claim that an unseen key/candidate exists.

Only UIAutomator clicks on the actual software keyboard and the test activity drive input. The test does **not** call
`setComposingText`, `commitText`, `performEditorAction`, `setText`, `UiObject.setText`, `UiDevice.pressKeyCode`, paste or
`adb shell input text`. It only reads the real `EditText` text/composing span, focus, selection, parent draft and
callback event order. It never installs or enables an IME, selects a subtype, writes secure settings or accepts terms.

The scenario requires:

1. Real `n` and `i` key clicks produce native `ni` composing text while the parent draft and commit callbacks stay
   unchanged, including across host recomposition.
2. Clicking the actual named candidate commits exactly that text and clears the native composing span.
3. A second native field takes focus without losing the committed draft; incrementing the original `focusRequest`
   restores focus without replacing selection and shows the software keyboard again.
4. The real Done control produces exactly one `onDraftCommit(candidate)` before one `onCommit()` and dismisses the
   keyboard.
5. Removing and recreating the generated host preserves the parent-owned committed draft. This is view recreation,
   not process-restoration evidence.

These checks are bounded to the supplied IME/version, subtype, Android build and target. They do not generalize to
other Chinese IMEs or keyboard layouts.

## Build only

Use JDK 21, Android SDK Platform 37.2 and the repository's pinned wrapper. From the repository root, regenerate and
stage the canonical fixture before compiling. The staged output is build-owned and ignored; do not replace it with a
hand-written host. The following Gradle invocation compiles both APKs but neither installs nor runs them:

```sh
swift build
python3 -I scripts/check_fixture_compilation.py
cd examples/android
./gradlew --no-daemon --max-workers=2 \
  :ime-verification:assembleDebug :ime-verification:assembleDebugAndroidTest
```

On the bounded Linux development host, run Swift and Gradle sequentially under
`systemd-run --user --scope -p CPUQuota=200% -p MemoryMax=4G -p TasksMax=256`; use `swift build --jobs 2`, Gradle
`--max-workers=2`, Gradle heap at most 1536 MiB and Kotlin daemon heap at most 1024 MiB. Compilation alone is not a
runtime result.

## Execute on a separately authorized target

The target owner must first allocate a specific already-running emulator or physical device, install and authorize a
named Chinese IME, select its Pinyin subtype through the native Settings/IME UI, and supply the exact component,
version, locale, mode and candidate. The owner must also verify that the software keyboard exposes its actual key and
candidate controls to accessibility/UIAutomator. Do not use a shared device without that allocation.

Bind `ANDROID_SERIAL` to that target only; do not let a command choose an arbitrary attached device. Keep the Gradle
invocation serial and bounded. The required values below are placeholders, not detected IME evidence:

```sh
export ANDROID_SERIAL=<owned-target>
./gradlew --no-daemon --max-workers=2 :ime-verification:connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.requiredIme=<package>/<service> \
  -Pandroid.testInstrumentationRunnerArguments.requiredImeVersion=<version> \
  -Pandroid.testInstrumentationRunnerArguments.requiredImeLocale=<locale> \
  -Pandroid.testInstrumentationRunnerArguments.requiredImeMode=<pinyin-mode> \
  -Pandroid.testInstrumentationRunnerArguments.requiredTarget=<owned-target-name> \
  -Pandroid.testInstrumentationRunnerArguments.requiredHostClass=<emulator-or-device> \
  -Pandroid.testInstrumentationRunnerArguments.requiredCandidate=<visible-Han-candidate>
```

If key text/content descriptions are ambiguous, obtain the target owner's actual keyboard resource IDs and add
`-Pandroid.testInstrumentationRunnerArguments.imeKeyResourcePrefix=<package>:id/key_`; do not bypass the resulting
failure with synthetic text. Done must be one unambiguous visible `Done`/`完成` text or content description in the
named IME package; otherwise supply `-Pandroid.testInstrumentationRunnerArguments.imeDoneResourceId=<package>:id/done`.
Do not use a key-event or direct-editor fallback for a keyboard whose controls cannot be identified.

Retain the connected-test XML, `REAL_IME_TARGET` and `REAL_IME_RESULT` logcat lines, the generated-source/golden check,
and target/IME screenshots reviewed for private metadata before publication. Report host type explicitly as emulator
or physical device. A fail-closed prerequisite error is evidence of an unmet target/keyboard prerequisite, not a
passing real-IME test.
