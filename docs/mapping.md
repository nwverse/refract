# Design-system mapping: `refract.json`

`refract.json` resolves names in the Swift subset to the application's existing Compose and ArkUI code. Resolution is
entirely a build-time operation. Generated source contains the selected native calls and token references; it never
reads this file, interprets a mapping at run time or imports a Refract library.

The published, normative structural schema is `Sources/RefractMapping/Resources/refract.schema.json`, using JSON
Schema 2020-12. `schemaVersion` is the integer `1`; adding fields still requires a schema, loader, diagnostics and
fixture update. Unknown keys and unsupported versions are errors rather than ignored extensions. The earlier
native-component-only `version: 1` draft is a distinct compatibility input, not an alias for the full schema; its
normalization and the policy for future incompatible changes are specified in `docs/cli.md`.

## Ownership and inputs

- The Swift source owns the component's cross-platform interface and semantics. The mapping cannot silently rename
  a source argument, drop a required argument or omit its children.
- Each platform entry owns its target symbol, argument spelling and ordering, imports and token references. The
  application owns the referenced design-system declarations on all three platforms, including ordinary SwiftUI
  declarations on iOS.
- Both platform entries must exist. Their component/native-component names, parameter labels, types, requiredness,
  modifier names and resource keys must agree. An absent platform implementation is an error, never a platform
  fallback.
- A component named in the source must be declared in `components`; a source `RefractNativeView` must instead be in
  `nativeComponents`. Neither kind falls back to a same-named native call. `docs/interop.md` owns the Swift marker
  declaration and source type-checking rules; this registry owns the two native implementation bindings.
- `resources.strings` is a manifest of application-owned localized keys to native resource names. `docs/subset.md`
  and the localization workstream own the Swift forms, key normalization and formatting rules. Refract neither
  invents missing resources nor generates an application resource table implicitly.

## Outputs and command-line precedence

Each platform has an `output.directory`, a normalized relative POSIX path without `.`/`..`, an absolute path, a
backslash or a trailing slash. Android additionally declares `output.packageName`. These defaults let the generator
place one output per input file without assuming a host application layout. Explicit `--android-out` and
`--harmony-out` CLI paths override the corresponding configured directory; they do not change its package name.

Android `imports` are fully qualified symbols, emitted in their listed order. HarmonyOS `imports` are objects with a
`module` and one or more named `symbols`; there are no arbitrary source snippets, wildcard imports or implicit global
initializers. Duplicates are errors. The mapping author includes the imports needed by mapped calls and modifier
chains. The platform compiler checks that referenced symbols and their native types exist.

## Components and parameters

Every entry under `components` has this common part in each platform object:

```json
{
  "parameters": [
    { "label": "title", "type": "string", "required": true },
    { "label": "action", "type": "action", "required": true }
  ],
  "content": "none",
  "modifiers": ["padding"],
  "target": "PrimaryButton",
  "argumentStyle": "named",
  "arguments": [
    { "source": "title", "target": "title" },
    { "source": "action", "target": "onClick" }
  ],
  "modifierParameter": "modifier",
  "attributes": {
    "padding": {
      "kind": "chain",
      "target": "padding",
      "arguments": [{ "source": "_" }]
    }
  }
}
```

The repeated common interface is intentional: a difference between Android and HarmonyOS is diagnosed at load time,
not left for a screen to discover later. JSON object order does not affect registry lookup; arrays retain their
explicit order.

- `label` is the Swift external argument label, or `_` for an unlabeled argument. Labels are unique within a
  component. `required` defaults to `true`. A target may rename or reorder parameters, but every required source
  parameter must occur exactly once. Optional parameters may be omitted only when the native declaration supplies
  the same default behavior.
- Scalar types are `string`, `bool`, `int`, `double`, `length`, `color`, `font`, `image` and `stringKey`.
  `length` is a native dimension (for example a Compose `Dp` and an ArkUI number), `font` is the target's native
  text-style value, and `color` is its native color value. `stringKey` is an already resolved localized text value,
  not permission to emit a literal. At a `RefractNativeView` boundary, `image` accepts only a static
  `Image("resource_name")` argument and `remoteImageLoader` names the app-provided native loading interface. Neither
  permits an arbitrary object or target expression. The loader must be an explicit typed input of the source screen;
  see `docs/remote-images.md` for the bounded lifecycle and platform evidence. Callback types are `action`,
  `actionString`, `actionBool`, `actionInt` and
  `actionDouble`. A `string`/`bool`/`int`/`double` parameter may read a declared model's matching scalar property;
  Compose reads the generated `State<T>` through `.value`, while ArkUI uses its direct property reference. Mapping
  validation and source typing compare these types; platform compilation then checks the concrete native types.
  Arbitrary Swift expressions, generic type names and structural object types are outside v1.
- `argumentStyle` is `named` (Compose-style `name = value`), `object` (one typed ArkUI options object), or
  `positional`. `target` is required for named/object arguments and forbidden for positional arguments.
- `content` is `none` or `children` in the common declaration. The platform spelling is `none`, `trailingClosure`,
  `parameter` (with `contentParameter`), or `builder`. A children-bearing source cannot become `none`. ArkUI builder
  content is emitted inside the component's braces; Compose trailing or named closures remain composable lambdas.
- `modifiers` lists exactly the source modifiers supported on that component. Top-level `modifiers` declare their
  typed parameters. Component `attributes` bind each accepted modifier either to a call `parameter` or to a direct
  one-call `chain`. `modifierParameter` names the native modifier receiver when a chain is possible (normally
  `modifier` in Compose). On ArkUI a chain is an attribute method; on Compose it is a `Modifier` call. V1 only
  forwards the declared values directly: it does not encode arbitrary Kotlin/ArkTS template expressions, a sequence
  of transformations, runtime modifier objects or string substitution. Such a modifier remains unsupported until a
  typed lowering is added.

Built-in views use the same registry when a project maps them. There is no second set of implicit component
mappings in `RefractMapping`. Standard platform layout primitives may be explicit mapping targets when the project
uses them as its design system.

## Tokens

`tokens` has `spacing`, `radius`, `font` and `color` tables. A key is the fully qualified Swift token reference used
in the source; its value is the fully qualified native symbol. For example:

```json
"tokens": {
  "spacing": { "DesignSpacing.medium": "AppSpacing.medium" },
  "radius": { "DesignRadius.small": "AppRadius.small" },
  "font": { "DesignTypography.body": "AppTypography.body" },
  "color": { "DesignColors.primary": "AppColors.primary" }
}
```

A source token must occur in the selected platform's table. Both platforms declare exactly the same keys, and a key
cannot occur in two categories. Spacing and radius produce `length`, font produces `font`, and color produces
`color`. A token used where its value type is incompatible is an error; no raw number, color literal, default style
or other token is substituted. The iOS SwiftUI target supplies ordinary native definitions for the same source
names, while Android and HarmonyOS supply definitions of their respective native value types.

## Resources

Android resources declare `className` (the application's fully qualified `R` class). HarmonyOS resources declare
`namespace` and `stringTable`. Each may declare `catalog`, the path to its base native string-resource file, resolved
relative to `refract.json`. Localized generation requires this path; registry-only configurations remain useful for
loader and component tests but cannot silently generate a resource lookup without the actual catalog.
Both have a `strings` dictionary from the localized source key to its native resource
name; names are lower-case ASCII identifiers with underscores; in v1 it must equal the key with dots replaced by underscores on both
platforms. Keys use lowercase ASCII letter-led alphanumeric dot-separated segments. The key sets and
normalized names must agree. Resource APIs are emitted directly (`stringResource` plus `R.string`, or `$r` with the declared table),
so a missing key is a compile-time diagnostic rather than a runtime lookup failure. `docs/localization.md` defines
catalog parsing and typed formatting. `docs/asset-catalogs.md` defines the opt-in image/font/raw catalog roots,
qualified binary resources, accessibility and app-owned raw/font boundaries. Those resource names are never
runtime lookup keys or arbitrary filesystem paths.

## System symbols

`symbols` maps a Swift `Image(systemName:)`/`Label(systemImage:)` name to a typed native icon or application media
resource. Both platforms must declare the same source names. Android uses `materialIcon` for the explicitly supported
v0 set (`Settings`, `Person`, `Check`) or `drawable` for an app-owned drawable name; HarmonyOS uses `media` for an
app-owned media resource name. A missing symbol or wrong platform kind is a build-time error, never a guessed
`sys.media` fallback. A legacy mapping without `symbols` retains the previous diagnostics for unmapped images; once a
registry is declared, all referenced symbols are resolved and validated before generation.

## Native components

`nativeComponents` uses the same typed declaration and target binding representation as `components`. Keeping a
separate registry prevents an ordinary design-system mapping from accidentally satisfying a native interop
declaration. The source marker declaration is compared with the common parameters and content on both platforms;
missing entries, labels, types or argument bindings stop generation. Implementations remain hand-written native
functions/components with no reflection or name-based discovery. A native entry can be mapped before a screen uses
it; an unused entry alone does not force an import into unrelated generated files.

## Validation and diagnostic order

Loading and generation report stable `Diagnostic` values with the shared rendered form
`refract.json:<line>:<column>: error [<code>]: <message> Suggestion: <alternative>` Mapping locations point to the key or
value responsible, with one-based coordinates. Source-use errors point to the Swift expression instead.

| Code | Meaning |
| --- | --- |
| `mappingIO` | The mapping cannot be read as UTF-8. |
| `mapping.invalid_json` | Malformed JSON, including the unexpected token's coordinate. |
| `mappingDuplicateKey` | Two identical object keys, rather than last-value-wins decoding. |
| `mappingVersion` | A schema version other than the supported integer. |
| `mappingUnknownKey` | A key not in the published schema, with its object path. |
| `mappingRequired` | A required key is absent. |
| `mappingType` | A JSON value has the wrong structural type. |
| `mappingValue` | An enum, pattern, count or numeric constraint fails. |
| `mappingOutput` | An output path or package is unsafe or malformed. |
| `mappingImport` | An import is duplicated or malformed. |
| `mappingParameter` | A target argument is unknown, repeated, missing or positionally labelled. |
| `mappingContent` | Content is dropped or its parameter declaration is inconsistent. |
| `mappingModifier` | A modifier declaration or attribute binding is inconsistent. |
| `mappingPlatformMismatch` | The two platform interfaces or resource key sets differ. |
| `mappingToken` | A token key is duplicated across categories or has an invalid target. |
| `mappingResource` | A resource declaration is incomplete or malformed. |
| `missingComponentMapping` | A source component has no mapping on the selected platform. |
| `missingNativeMapping` | A native source declaration has no native implementation mapping. |
| `componentArgument` | A source argument is missing, unknown or has an incompatible type. |
| `unsupportedComponentModifier` | The component does not declare this modifier. |
| `missingTokenMapping` | A referenced token is absent on the selected platform. |
| `missingResource` | A localized key is absent on the selected platform. |

The golden runner expands `MappingError` so independent Swift and mapping diagnostics are both reported before
output is skipped. Errors are deterministic: JSON order for object validation, declaration order for arrays, Android before HarmonyOS,
and source order for use-site diagnostics. A load error prevents both outputs from being written. Resolution never
returns partial source or a best-effort native call.

## Design and fixture evidence

`Fixtures/mapping/brand-a/Input.swift` and `Fixtures/mapping/brand-b/Input.swift` are deliberately byte-identical.
Their complete mappings select different application components, parameter names, token references, imports and
output packages. Their hand-written Kotlin and ArkTS expectations contain only direct native calls. Validation
fixtures cover missing mappings, cross-platform interface drift and malformed schema values. The golden runner
validates every declared case; `pending` is an explicit implementation state, never a silent skipped test.

Performance is structural here: resolution happens once at build time, imports are explicit, and generated value and
modifier calls are the calls an application developer would write. There is no runtime registry, dynamic resource
lookup or extra view wrapper. Platform compilation and representative generated-vs-native benchmarks remain the
verification responsibilities of the backend, example and performance workstreams.
