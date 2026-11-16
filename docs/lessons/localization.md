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
- **Linux XML APIs live in FoundationXML.** Import that module conditionally. Do not import `RefractMapping` from
  its own source file; Swift warns about a module self-import.
