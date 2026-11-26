# Fixture coordination lessons

- **Check the merged contract, not only an issue proposal.** Parallel design drafts used different diagnostic
  separators, model ownership and resource spellings. Read the shared renderer and merged state document before
  freezing golden files, and record a deliberate contract change on the owning issue.
- **A corpus cannot silently skip unsupported cases.** An explicit manifest distinguishes ready golden execution
  from pending backend implementation. Structural checks cover every case, including pending cases; a pending case
  never counts as a passing generation test. A manifest and its directories must match exactly.
- **Keep the input real SwiftUI.** A wrapper or marker that only the generator provides would make iOS depend on a
  library. Source-declared empty markers are permitted; generated model and native boundaries must remain ordinary
  source consumable by the consuming application.
- **Hand-written expectations are a semantic review, not formatting.** Check identity, observation, accessibility,
  resource semantics, list laziness and ordinary public native signatures. Regeneration verifies the implementation;
  it does not decide what correct native code should be.
- **Modifier order is not universal semantics.** Compose modifier order affects rendering; a SwiftUI background
  followed by a corner radius should become a shaped `background(color, shape)`, not a rectangular background with
  later clipping. ArkUI background color and border radius are attributes, not that same ordered operation.
  Review the rendered result, not just a one-call-per-source-modifier mapping.
- **Do not invent default spacing.** An omitted SwiftUI stack `spacing` is not a universal 8 dp/fp value. Leave
  native default behavior intact unless the source supplies a typed spacing token. Explicit values still need a
  common typed representation accepted by both backends.
- **A diagnostics-only golden must reject native output too.** Comparing only non-nil native expectations lets an
  empty `Expected.diagnostics` accept successful generation with no output review. Reject that empty shape at load,
  and make any native result for a diagnostics-only case a mismatch even when the expected diagnostic also differs.
- **Generated-source staging must not own native support code.** `check_fixture_compilation.py` removes its Java and
  resource staging trees before each run. Hand-written native components belong in a separate source set (for
  example `src/native`), referenced by the Android `sourceSets.getByName("main").kotlin` container in AGP 9.
  Kotlin Multiplatform's `kotlin.sourceSets["main"]` does not exist here.
- **Compile a styled golden before changing its imports.** A shaped Compose `background(color, RoundedCornerShape(...))`
  still requires `androidx.compose.foundation.background`; only the separate `clip` import is unnecessary. Do not
  remove imports merely because the shape is fused in the call. Review token provenance on both targets and verify
  that an ArkUI modifier-token import collector follows the same mapping, not a source-name heuristic.
- **Target-specific collection boundaries need explicit semantics.** ArkUI `LazyForEach` consumes `IDataSource`;
  an array-to-data-source mirror can miss changes or add work. The source contract must say who owns updates instead
  of hiding synchronization in `build()` or an undocumented lifecycle callback.
