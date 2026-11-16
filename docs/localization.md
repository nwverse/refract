# Localization: one key, two native resource catalogs

Refract resolves user-facing strings during generation. Generated source calls the platform's resource APIs directly;
it does not ship a localization runtime, read `refract.json`, query resources by a dynamically constructed name or
fall back to displaying the source key. The application owns its resource files on all three platforms.

This page specifies resource-file validation and formatting. `docs/subset.md` is the source-language contract and
`docs/mapping.md` owns the common mapping registry and resource lookup diagnostics.

## Source forms

```swift
Text("settings.title")
Text(LocalizedStringKey("settings.title"))
Text("profile.greeting\(name)\(count)")
Text(verbatim: "Debug build")

let accessibilityText = String(localized: "settings.title")
```

- A static string in a user-facing position is a **localization key**, not text to display literally. Dynamic key
  expressions are rejected: the key must be recoverable from the source literal.
- `Text(verbatim:)` is the explicit escape hatch for intentional non-localized text. It remains a literal in both
  generated outputs, with target-language escaping. Other literal-looking text in user-facing positions is diagnosed
  unless it is a valid canonical key; it is never silently copied.
- Interpolation is ordinary SwiftUI `LocalizedStringKey` interpolation. The static parts form the lookup key; each
  interpolation becomes an ordered argument. Formatting and plural choice stay in translator-controlled resources,
  not embedded into the key or generated with string concatenation. Each argument must have a statically known
  `String`, `Int` or `Double` type. Arbitrary interpolation, locale-sensitive formatting calls and `Bool` are
  rejected rather than approximated. Explicit screen inputs retain their scalar type in the IR and native signature.
  The literal portions around interpolation must form a valid canonical key, so punctuation and whitespace needed
  for display belong in the resource, not beside the interpolation in the source key.
- `String(localized:)` supplies a resolved string for another supported argument. An explicitly constructed
  `LocalizedStringKey` requires a literal key, not a runtime-selected key. These forms preserve the same source on
  iOS; there is no Refract dependency in that source.

The initially considered `String(localized:arguments:)` array spelling is **not** accepted: it is not a portable
Foundation API. Formatted view text uses SwiftUI interpolation instead. No unverified Apple-only overload is part of
the v0 source contract.

## Canonical keys and resource names

A key contains one or more nonempty dot-separated segments. A segment starts with a lowercase ASCII letter and then
contains only lowercase ASCII letters or digits:

```text
settings.title     -> settings_title
profile.message2   -> profile_message2
```

The same normalized name is used by **both** platforms:

```kotlin
Text(text = stringResource(R.string.settings_title))
```

```ts
Text($r('app.string.settings_title'))
```

Underscores, uppercase letters, hyphens, whitespace and non-ASCII characters are not accepted in v0 keys. Because
input keys cannot contain underscores, replacing dots with underscores is injective: two distinct valid keys cannot
silently select the same native entry. Do not replace every punctuation character with `_`, and do not use a dotted
key on one platform but an underscored name on the other.

`Text("Hello")` therefore produces `R.string.invalid_key`, not an implicit `hello` resource. `Text("settings_title")`
also produces that diagnostic rather than aliasing `settings.title`.

## Native catalogs

The mapping declares each platform's base string-resource file, alongside the `resources.strings` registry owned by
the mapping workstream. A generation input resolves relative paths against the mapping file's directory. Absolute
paths are generator inputs only and never occur in generated code.

| Platform | Required catalog | Example path in mapping |
| --- | --- | --- |
| Android | `values/strings.xml`, `<resources>` with direct `<string>` children | `src/main/res/values/strings.xml` |
| HarmonyOS | `resources/base/element/string.json`, `{ "string": [{ "name": ..., "value": ... }] }` | `src/main/resources/base/element/string.json` |

Only base files are read for existence. Locale-qualified Android `values-<qualifier>` and HarmonyOS
`resources/<qualifier>` directories may provide translated values but cannot introduce a key that is missing in the
base catalog. This is a build-time completeness check, not generation or synchronization of translated resources.
A missing, unreadable or malformed configured file is an error even when its registry entry exists.

Android entries must be direct, translatable `<string>` children of `<resources>` with a `name`. Arbitrary markup,
including styling and inline substitution markup, is rejected until its semantics are implemented on both platforms.
HarmonyOS entries require only the documented string `name` and `value`; `attr` metadata is optional. Empty string
values are valid. XML entity references are decoded before comparing format placeholders.

## Format arguments

Use only `%%` and contiguous, one-based, typed placeholders:

| Swift argument | Placeholder | Example |
| --- | --- | --- |
| `String` | `%1$s` | `Hello %1$s` |
| `Int` | `%2$d` | `%2$d items` |
| `Double` | `%3$f` | `Progress: %3$f` |

For example, both base catalogs define `profile_greeting` as `Hello %1$s, you have %2$d items`. The generated calls
are:

```kotlin
stringResource(R.string.profile_greeting, name, count)
```

```ts
$r('app.string.profile_greeting', this.name, this.count)
```

OpenHarmony's resource-access contract supports formatting arguments directly on `$r`; an extra
`ResourceManager.getStringSync` wrapper is unnecessary. Compose uses the ordinary `stringResource` overload. The
platform owns locale selection, argument ordering and plural-aware resource selection as it does for hand-written
code. No conversion helper, interpolation buffer or format parser is generated.

Every referenced argument must occur at its declared position. Duplicate positions, gaps, implicit positions,
zero/negative positions, unsupported types, flags, width, precision, length modifiers and unsupported conversion
characters are errors. Both catalogs must agree on the number and ordered types of arguments; translations may reorder
those explicitly numbered placeholders but cannot change their types or omit them. Android `formatted="false"` does
not waive this check.

Dynamic quantities are values, not a promise to infer Apple/Android/Harmony plural rules automatically. The
application supplies the appropriate platform resource forms and locale-specific text. No language's plural rules
are guessed from a numeric argument.

## Diagnostics and output ordering

Codes use `R.string.*`, matching the generator's existing diagnostic namespace and the mapping resource failures.
Each diagnostic points to the source expression or configured resource where available, explains the problem and
suggests a specific correction.

| Code | Failure |
| --- | --- |
| `R.string.literal` | User-facing text is not a valid key or explicitly verbatim |
| `R.string.invalid_key` | Key is not canonical, or is dynamically selected |
| `R.string.not_configured` | No resource registry/catalog is configured |
| `R.string.missing_android` | Android registry/catalog entry is absent |
| `R.string.missing_harmony` | HarmonyOS registry/catalog entry is absent |
| `R.string.invalid_resource` | Resource file structure, encoding or entry is invalid |
| `R.string.duplicate_resource` | A base catalog repeats a resource name |
| `R.string.unsupported_format` | A placeholder is not in the portable subset |
| `R.string.format_arguments` | Catalogs or source disagree on argument count/types |
| `R.string.interpolation` | Interpolation type or expression is unsupported |
| `R.string.unsupported_expression` | IR text provenance is not localized or explicitly verbatim |

Frontend diagnostics precede resource diagnostics. For the same source expression, mapping lookup checks Android
before HarmonyOS. Catalog parsing is deterministic; dictionary iteration never controls output order. Any error
prevents both generated files from being committed, rather than emitting one platform or a placeholder.

## Fixtures and verification boundary

The shared corpus includes plain resource text, typed formatted text, explicitly verbatim text, and missing keys on
each backend. Expected Kotlin and ArkTS are hand-written native references. Generator tests additionally cover
canonical-key collisions, decoded XML, duplicate entries, malformed formats and platform format disagreement.

The golden suite verifies deterministic source generation, not the platform toolchain. Android and HarmonyOS
compilation belongs to the examples; Apple-SDK compilation of interpolated SwiftUI text requires macOS/iOS and is
not claimed by Linux-only tests.
