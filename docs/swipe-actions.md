# Bounded native swipe/archive actions

`Fixtures/interop-swipe-archive/` defines one native row for an identified dynamic list. It does not add a gesture
interpreter, an arbitrary modifier closure, a shared confirmation registry or an animation runtime. The generated
screen passes one row's stable String identity to the application-owned `NativeSwipeArchiveRow` implementation.

## Closed source and native ABI

The accepted component is exactly `NativeSwipeArchiveRow`, directly owned by `List(model.items)` or
`List { ForEach(model.items) }`, whose item has a stored String `id`. It takes these parameters in declaration order:

```swift
let identifier: String
let title: String
let onRequest: (String) -> Void
let onConfirm: (String) -> Void
let onCancel: () -> Void
```

The only accepted source shape is:

```swift
NativeSwipeArchiveRow(
    identifier: item.id,
    title: item.title,
    onRequest: { identifier in model.requestArchive(identifier) },
    onConfirm: { identifier in model.archive(identifier) },
    onCancel: { model.cancelArchive() }
)
```

`onRequest` and `onConfirm` must forward their closure argument unchanged to one declared unlabeled String model
method. `onCancel` must be the existing checked zero-argument model action. A different closure, an unrelated action,
a missing id, a non-String id or a non-list receiver is `RFSWIPE001`/`RFSWIPE002`, not a generated approximation.
The mapping validator independently requires this exact component signature, including Kotlin
`(String) -> Unit`/ArkTS `(string) => void` and `() -> Unit`/`() => void` callbacks. This does not widen the existing
link-only String-action ABI to arbitrary components or Screen closures.

The source body is an app-owned ordinary SwiftUI sketch with a native swipe action, an explicit Button alternative
and a confirmation dialog. Its private `@State isConfirming` is iOS implementation state only, explicitly whitelisted
on this one component and never emitted as a sixth native argument. Other native components cannot use that exception.
It is not a shared animation specification and is not translated into another platform's implementation.
on this one component and never emitted as a sixth native argument. Other native components cannot use that exception. It is not a shared animation specification and is not translated into another platform's
implementation. On HarmonyOS, the mapping delegates the same typed inputs to the app's `NativeSwipeArchiveRow`; its
implementation, compiler and lifecycle are not verified here.

## Shared confirmation, cancellation and motion

The Android fixture implementation owns one pending identity for the row. A short end-swipe exposes the native
archive affordance and requests the same confirmation as the explicit action; it never archives directly. Both the
revealed action and the explicit `Row actions` DropdownMenu invoke `onRequest(identifier)` and show the same native
`AlertDialog`. An accessibility custom action uses that request path as well. No action archives before confirmation.
The pending dialog is idempotent while visible, so a completed swipe and its revealed action cannot request twice.

Confirmation calls `onConfirm(identifier)` only while the pending identity and request-local generation still match
the current row. A stale confirmation for a replaced or disposed request is discarded instead of archiving the new
item. `DisposableEffect(identifier)` clears obsolete pending state and invokes the existing `onCancel` action only
when that request was still pending. This is how the app clears its retained pending business state; no additional
model method, callback registry or runtime gesture state machine is added.

Dismissal or the Cancel button calls the same `onCancel` and never invokes the archive method. The pending dialog is
closed before the confirm/cancel action, and both paths reset the native swipe state. Normal completion does not emit
a second cancellation. Returning to the screen does not replay the disposed confirmation.
Confirmation calls `onConfirm(identifier)`. Dismissal or the Cancel button calls the same `onCancel` and never invokes
the archive method. The pending dialog is closed before the confirm/cancel action, and both paths reset the native
swipe state. The model implementation is responsible for retaining/clearing its corresponding business pending state;
there is no hidden runtime model or registry in Refract.

The fixture uses native `SwipeToDismissBox`. A partial swipe may settle back to its native resting position; this
contract does not invent a persistent reveal state. Normal motion uses `reset()`. At zero `MotionDurationScale` it
uses `snapTo(SwipeToDismissBoxValue.Settled)` for explicit settling, without a second timer or a generated animation
DSL. Native cancellation/disposal belongs to the app implementation and native coroutine scope.

## Evidence and limits

The real CLI regenerates both `Expected.kt` and `Expected.ets`. `interop-swipe-reject-action` rejects a confirmation
closure that does not forward the identifier, and `interop-swipe-reject-receiver` rejects a VStack-wrapped component
with `RFSWIPE001` before either backend writes output. The direct-row golden remains byte-identical. Generated calls preserve `item.id`, title and all three
closure that does not forward the identifier; focused tests also cover non-String row identity, wrong component shape
and the unchanged restriction on unrelated String actions. Generated calls preserve `item.id`, title and all three
checked callbacks on both backends.

`examples/android/fixtures/src/native/java/com/example/refract/gesture/NativeSwipeArchiveRow.kt` is compiled with the
unmodified CLI-generated list. Native JVM Compose/Robolectric tests drive that generated screen through short swipe,
revealed-action confirmation, menu cancellation/confirmation and zero-motion settling. Separate lifecycle tests exercise
pending-request idempotence, identifier replacement and leaving composition on the same app-owned native component.
A stale-confirmation gate test rejects replacement and generation mismatches while accepting the current pending
identity; the generated confirm button uses that gate. Leaving and returning does not replay pending confirmation.
These are not emulator, device, physical gesture or performance results. iOS source and ArkTS native components are
source/golden evidence only, not native compilation claims.
pending-request idempotence, identifier replacement and leaving composition on the same app-owned native component. They are not emulator,
device, physical gesture or performance results. iOS source and ArkTS native components are source/golden evidence only, not
native compilation claims.

Run after a bounded `swift build`:

```sh
python3 -I scripts/check_fixture_compilation.py
examples/android/gradlew -p examples/android --no-daemon \
  :fixtures:compileDebugKotlin :fixtures:testDebugUnitTest
```
