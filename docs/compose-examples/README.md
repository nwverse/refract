# Compose examples

Hand-written Swift input and the exact Kotlin the Compose backend is expected to emit for it. These are design
examples, not the conformance corpus: the conformance corpus lives in `Fixtures/` and is owned by #2 with the
runner from #1. Once those land, every example here moves into `Fixtures/<case>/` unchanged.

The purpose of this directory is to fix the Kotlin shape **before** the emitter exists, so the implementation is a
transcription rather than a design exercise. Each example follows `docs/compose-backend.md`; if the two disagree,
the doc is wrong and is corrected.

Format: one directory per case, with `Input.swift`, `Expected.kt`, and an optional `Notes.md` explaining the
choices. `refract.json` is omitted when the case uses only platform defaults; when a case needs design-system
mappings the mapping is shown inline in `Notes.md`.

## Cases

| Case | What it pins down |
| --- | --- |
| `hello-text` | The smallest possible screen: one `Text` in a `VStack`. File header, package, imports, `@Composable`, `modifier` parameter. |
| `vstack-spacing` | `VStack(spacing:alignment:)` → `Arrangement.spacedBy` + `horizontalAlignment`. |
| `hstack-spacing` | `HStack` → `Row`, `Arrangement.spacedBy`, `verticalAlignment`. |
| `zstack-alignment` | `ZStack(alignment: .topLeading)` → `Box(contentAlignment = Alignment.TopStart)`. |
| `text-modifiers` | `.font`, `.foregroundColor`, `.padding` on a `Text`: parameter vs modifier split. |
| `padding-forms` | `.padding()`, `.padding(16)`, `.padding(.horizontal, 16)` → three `Modifier.padding` shapes. |
| `frame-forms` | `.frame(width:height:)`, `.frame(maxWidth: .infinity)` → `size` vs `fillMaxWidth`. |
| `button-action` | `Button("Title") { … }` → `Button(onClick) { Text }`, remembered lambda. |
| `conditional-if-else` | `if flag { A } else { B }` → Kotlin `if`. |
| `conditional-if-let` | `if let x = opt { … }` → smart-cast `if (x != null)`. |
| `switch-enum` | `switch` over a Swift enum → exhaustive `when`. |
| `list-lazy-column` | `List(items)` over `Identifiable` data → `LazyColumn` with `key` and `contentType`. |
| `scroll-view` | `ScrollView { VStack { … } }` → `Column(verticalScroll(rememberScrollState()))`. |
| `nested-containers` | A realistic screen skeleton: `VStack` of `HStack`s and `Text`s. |
| `diagnostic-image-system-name` | `Image(systemName:)` → `RF-C002`. |
| `diagnostic-foreach-no-id` | `ForEach` over non-identifiable data → `RF-C003`. |

## Why hand-written

Expected output is never produced by the code under test. If a future refactor changes the emitter, these files
do not move unless a human edits them, so a diff is always a deliberate decision (goal 1, goal 3).
