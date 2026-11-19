# Native string resources

- **A source key is not a fallback translation.** `Text("...")` must resolve to application-owned Android and
  HarmonyOS catalogs. Literal user-facing text requires `Text(verbatim:)`; never emit an unresolved key as visible
  text.
- **Use one native name on both platforms.** Canonical dot-separated keys cannot contain underscores, so replacing
  dots with underscores is reversible. `$r` and `R.string` therefore use the same normalized name.
- **Do not invent a Foundation formatting API.** The proposed `String(localized:arguments:)` spelling was rejected by
  the installed compiler. Formatted view text uses ordinary SwiftUI interpolation; validate its typed arguments.
- **Preserve native resource formatting.** OpenHarmony documents `$r('app.string.name', args...)`. Compose's
  `stringResource` also accepts arguments. No resource-manager wrapper is needed.
- **Test empty formats.** `(1...maximum)` crashes when no placeholders exist (`maximum == 0`). Return `[]` explicitly
  and test argument-free strings, not only formatted ones.
- **Linux XML APIs live in FoundationXML.** Apple SDKs instead export `XMLDocument` and `XMLElement` from
  `Foundation`, with no standalone `FoundationXML` module. Keep `import Foundation` and guard the extra import with
  `#if canImport(FoundationXML)` in tests as well as production sources; an unconditional import breaks the required
  macOS dependency scan before tests run. Do not import `RefractMapping` from its own source file; Swift warns about a
  module self-import.
- **Keep frontend dependencies one-way.** Key syntax belongs in IR; `RefractFrontend` cannot call a helper in
  `RefractMapping` just because both modules need it. Mapping and backend code may depend on IR, not the reverse.
- **Do not compare repackaged SwiftSyntax members by identity.** Filtering a member list creates new syntax values;
  compare the declaration's semantics (for example the `body` binding name) rather than relying on a wrapper's `id`
  or trivia-sensitive position.
- **Separate registry and catalog failures.** The mapping must declare a key on both platforms, but the native base
  resource file must also contain it. A missing-key fixture should omit the key from only the layer being tested.
- **Escape fixture interpolation twice.** A Swift test string containing an input such as `Text("key \\(value)")`
  needs `\\(value)` in the host literal. Otherwise the test compiler evaluates the interpolation instead of the
  parser under test.
