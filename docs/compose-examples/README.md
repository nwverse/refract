# Compose examples

Hand-written Swift input and the intended Kotlin for each Compose lowering decision. These are design examples,
not the conformance corpus: the executable corpus lives in `Fixtures/`, and the generator and its golden runner
are now available. Examples are promoted only after frontend support, an IR contract and hand-reviewed expectations
are ready; they are not executed by the golden runner merely because they live here.

This directory records the Kotlin shape chosen for each construct. Each example follows `docs/compose-backend.md`;
a disagreement is a design issue to resolve explicitly, not a reason to overwrite either side automatically.

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
