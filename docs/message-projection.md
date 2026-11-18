# Bounded message projection

This document specifies issue [#222](https://github.com/nwverse/refract/issues/222): a bounded, typed message
append/update/finalize projection and the native presentation of its immutable snapshots. It does not define a chat
transport, a streaming runtime, a rich-text AST or a selection callback ABI.

## Ownership and bounded source contract

The application owns all business logic. Refract generates data and view declarations, never a projection state
machine, network subscriber, event bus or model mirror. `Fixtures/chat-message-projection/Input.swift` declares:

```swift
struct ChatBlock: Identifiable {
    let id: String
    let text: String
}

struct ChatMessage: Identifiable {
    let id: String
    let revision: UInt64
    let blocks: [ChatBlock]
    let finalized: Bool
}

protocol ConversationModel: RefractModel {
    var messages: [ChatMessage] { get }
}
```

A generated `MessageBlock` child takes both the current `message` and `block`. Its body can read `block.text` and a
Bool such as `message.finalized`; it cannot introduce another nested collection. The only nested collection syntax
in this slice is `ForEach(message.blocks)` directly in a `ChatMessage` row's non-scrolling `VStack`. An ordinary
nested `List`, a different collection, missing independent ids, or an invalid message/block declaration is an
`RFMSG001` build-time error. There is no array-index or inferred-identity fallback.

The bounded names are part of the contract, not a request to translate arbitrary application model graphs. Other
Identifiable item types retain the existing scalar-only rules. The source `UInt64` revision maps to Kotlin `Long`
and ArkTS `bigint`, not `Int`/`number`. A native implementation must reject negative and above-`Long.MAX_VALUE`
transport revisions before conversion; the reference boundary accepts the positive `Long` subset. No truncation,
signed wraparound, double-precision conversion or arbitrary revision-width promise is made.

## Projection rules

`examples/android/fixtures/src/native/java/com/example/refract/chat/MessageProjection.kt` is hand-written
application code compiled against the generated model. It is not generated output and is not a Refract runtime.

- Message ids and block ids are independent stable `String` values. A block permanently belongs to one message;
  equal block ids in different messages are not a move operation.
- Every mutation carries a whole-message revision. Lower revisions are stale. An identical revision and identical
  append/update payload is a no-op; an identical revision with different payload is rejected. A conflicting higher
  revision after finalization cannot reopen or change the terminal payload.
- Append preserves the supplied block order and rejects repeated ids. Update replaces exactly one existing block
  in place; it cannot append a missing block or transfer it to another message.
- Finalize is terminal and idempotent. Repeating the accepted terminal revision and payload is a no-op; a later
  append or update is rejected. An unknown message, an empty identity, a duplicate identity, a conflicting revision
  and a capacity failure are explicit `ProjectionRejection` values, not silent loss.
- Message and per-message block capacities are explicit constructor inputs. There is no implicit FIFO eviction,
  truncation or capacity default hidden in the generated UI.
- Each candidate is validated completely before its immutable list is published and before block ownership is
  updated. An append containing a later duplicate is rejected as a whole. A rejected operation leaves the same
  published snapshot instance in place; no half-applied message or partially registered block is visible.
- Delivery is serial and application-owned. The projection does not pretend to supply cross-thread confinement,
  network ordering, process persistence, distributed conflict resolution or lifecycle cancellation.

A HarmonyOS implementation must apply the same native rules to its immutable snapshots and application-owned
`BasicDataSource`, including the required replacement notifications. That implementation and its observation
behavior are not supplied or verified by this slice.

## Native rendering and identity

Compose emits a `@Immutable ChatMessage` containing a `List<ChatBlock>`. `LazyColumn.items` uses `message.id`.
The bounded blocks become additional items in the **same** `LazyColumn` builder, keyed by a private typed
`refractMessageBlockKey(message.id, block.id)`, a Bundle-compatible String with length-prefixed UTF-16 ids, not a nested vertical `LazyColumn`. A `LazyListScope` builder helper
visits snapshots in source order and registers each nonempty message container followed by that message's blocks.
It does not create a flattened pair list or register lazy items from inside a composable item-content lambda.
A snapshot with no blocks contributes no empty parent container. `MessageBlock` remains an ordinary public
composable with explicit typed inputs.

ArkUI emits a typed `BasicDataSource<ChatMessage>` model property, a keyed outer `LazyForEach`, and a bounded
non-scrolling `ForEach(message.blocks)` within the row. `block.id` keys that inner loop. The source includes the
`revision: bigint` and `finalized: boolean` snapshot fields. A future app-owned native presentation can consume
these ids without a runtime registry; this issue does not generate a data-source adapter.

The generated `MessageBlock` presents `block.text` and the parent `message.finalized` condition. Like the existing
`Text(model.title)` and list-item `Text(row.title)` forms, a declared String item property is dynamic display
content, not a localization key; Unicode, punctuation and resource-name-shaped values remain literal runtime values.
Rich text, Markdown, UTF-16 selection ranges, links and AI-edit callbacks remain with #200/#201. This slice does
not add a selection callback ABI or claim native selection/lifecycle verification.

## Evidence and limits

- The real CLI generates and diffs both `Expected.kt` and `Expected.ets`. The source is also compiled as the
  byte-identical `examples/shared/ChatMessageProjection.swift` iOS target input when that target is built.
- `scripts/check_fixture_compilation.py` stages the real generated Kotlin and `./gradlew :fixtures:compileDebugKotlin`
  compiles it against the pinned Android dependencies. This is native compilation, not a device result.
- Plain Native JVM tests cover ordered append/update, duplicate no-ops, stale/conflicting revisions, terminal
  idempotence, atomic append/capacity rejection, block ownership, empty ids and the positive `Long` revision range.
- Native JVM Compose and TextView tests exercise the actual generated block child, appended/updated/finalized
  content, message/block ordering, empty-parent omission and native text display. Robolectric is a host-JVM
  environment, not an emulator, device or performance measurement. It does not establish IME, TalkBack or gesture
  parity, and no selection/lifecycle assertion is made by this slice.
- The `chat-message-reject-revision` golden and parameterized frontend tests reject invalid revision and collection
  declarations. They do not turn runtime projection failures into Swift diagnostics: those are native application
  errors with the documented atomic behavior.
- **iOS and HarmonyOS native compilation/runtimes are not verified here.** The iOS project reference and the
  source-level ordinary SwiftUI form are wiring evidence only. ArkTS is source-level evidence only; in particular,
  its compiler, `bigint` SDK integration, `ForEach` behavior and data-source observation require the authorized
  HarmonyOS toolchain. No simulator, emulator or device timing, render or selection result is claimed.
