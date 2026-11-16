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
- **Target-specific collection boundaries need explicit semantics.** ArkUI `LazyForEach` consumes `IDataSource`;
  an array-to-data-source mirror can miss changes or add work. The source contract must say who owns updates instead
  of hiding synchronization in `build()` or an undocumented lifecycle callback.
