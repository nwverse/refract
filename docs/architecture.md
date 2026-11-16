# Architecture

This is the initial design. It serves `docs/GOALS.md`; where the two disagree, the goals win and this page is
corrected. Decisions that are still open are listed at the end; resolve them in issues and record the outcome here.

## Shape

```text
Swift source (Refract subset of SwiftUI)
  │
  ├─ iOS: the same file is ordinary SwiftUI, compiled by swiftc. No Refract dependency.
  │
  └─ refract generate (build time)
       Frontend  SwiftSyntax → parse → resolve → check the subset → diagnostics
       IR        a typed, platform-neutral tree: views, modifiers, state, bindings, models, strings, native refs
       Lowering  IR + the project's mapping (refract.json) → per-platform IR with design-system calls resolved
       Backends  Compose (Kotlin)          ArkUI (ArkTS)
                  │                          │
                  ▼                          ▼
         committed .kt files          committed .ets files
         compiled by the app's        compiled by the app's
         Gradle build                 hvigor build
```

There is no Refract runtime library. Generated code calls only the platform SDK and the consuming app's own code:
its design-system components and tokens, its model implementations and its native components (goal 2).

## Components

| Module | Responsibility |
| --- | --- |
| `RefractIR` | IR types, source locations, the diagnostic type. Pure Swift, no SwiftSyntax dependency |
| `RefractFrontend` | SwiftSyntax parsing, name resolution within the input files, subset checking, building the IR |
| `RefractMapping` | Loads and validates `refract.json`: design-system components and tokens per platform, string resources, native component declarations |
| `RefractCompose` | IR → idiomatic Jetpack Compose source |
| `RefractArkUI` | IR → idiomatic ArkUI (ArkTS) source |
| `RefractCLI` | The `refract` executable: `generate`, `check`, `explain <diagnostic>` |

Later: a SwiftPM build-tool plugin, a Gradle plugin and an hvigor plugin that run `refract generate` and the
regenerate-and-diff check, so generation fits each platform's normal build.

The generator is written in Swift because SwiftSyntax is the reference parser for the language Refract accepts, and
because the people who write Refract screens already read Swift. It builds and runs on macOS and Linux.

## Input: the Refract subset

`docs/subset.md` is the contract: every accepted construct, its meaning on each platform, and the diagnostic for
each rejected one. In outline:

- **Views.** `struct X: View` with a `body`, built from supported containers (`VStack`, `HStack`, `ZStack`,
  `ScrollView`, `List`/`LazyVStack` with `ForEach` over identified data), leaf views (`Text`, `Image`, `Button`,
  `Toggle`, `TextField`, ...) and the project's own design-system components declared in `refract.json`.
- **Modifiers.** A supported set with a defined mapping per platform. Values come from design tokens, never literals,
  when the project's mapping declares tokens.
- **State.** `@State` (local), `@Binding` (parent-owned), and models: a protocol the screen declares (properties and
  actions) that the app implements. See "Models".
- **Control flow.** `if`/`else`, `switch` over enums, `ForEach`, `#if os(...)`-style per-platform variation through
  Refract's declared form (goal 5).
- **Strings.** `Text("key")` / `String(localized:)` keys resolved to each platform's resources.

Anything else is rejected at build time with a diagnostic that explains why and what to use instead (goal 3).

## Models: the data boundary

A screen depends on a model protocol, never on a concrete type:

```swift
protocol ExtensionSettingsModel: RefractModel {
    var title: String { get }
    var isEnabled: Bool { get }
    func setEnabled(_ value: Bool)
}
```

Refract generates the matching Kotlin interface (consumed with Compose state) and ArkTS interface (consumed with
ArkUI's observation, V2 decorators where available). Today the app's existing view models implement them; later a
shared core, such as a Rust library linked by every platform, can implement them without touching the screens
(goal 4). How models expose observable state to Compose and ArkUI so that only the views that read a value update
is a performance rule (goal 2) and is specified in `docs/performance.md`.

Open decision 3 is resolved for the first slice: Compose interfaces expose `State<T>` and read `.value` at the leaf;
ArkTS interfaces expose typed properties implemented by `@ObservedV2` classes with `@Trace` members, consumed through
`@ComponentV2`/`@Param`. The minimum ArkUI API is 12. `@Binding` lowers to a value plus setter callback on both
platforms; no observation adapter is generated. The detailed contract and evidence are in `docs/state-and-models.md`.

## Mixing with native code (goal 5)

- **Native components inside Refract**: declared once (name, parameters with types) in Swift or `refract.json`,
  implemented by hand on each platform. The generator emits a call and checks that the declaration and the
  platform implementation agree.
- **Per-platform variation**: a declared, type-checked construct in the Swift source selects a different value,
  modifier or animation per platform. Free-form `#if` blocks that hide arbitrary code are not accepted.
- **Generated code inside native**: generated components are plain public functions/components with documented
  parameters.

## Output

- One generated file per input file per platform, at a path the project configures, with a header naming the
  source file and Refract's version and saying "generated, do not edit".
- Deterministic: the same input and mapping produce byte-identical output on every machine.
- Idiomatic and formatted to each platform's standard style, so the diff of a Swift change is readable.

## Testing

- **Golden fixtures** are registered in `Fixtures/Corpus.json`. Each entry has a nested `path` relative to
  `Fixtures/` and an `implementationStatus` of `ready` or `pending`. Every case contains `Input.swift`, optional
  `refract.json`, and either both `Expected.kt` and `Expected.ets`, or `Expected.diagnostics`. All entries are
  structurally validated. Ready cases regenerate and diff; pending cases are reported as known issues, never as
  passing generation tests. Missing, duplicate or unlisted cases fail the suite. See `Fixtures/README.md`.
- **Compile checks**: the examples compile generated Kotlin with Gradle and ArkTS with the HarmonyOS toolchain where
  available; where a toolchain is unavailable the PR says so.
- **Benchmarks** in `bench/`: generated vs hand-written reference per platform (goal 2).

## Repository layout

| Path | Contents |
| --- | --- |
| `Package.swift`, `Sources/`, `Tests/` | The generator (SwiftPM) |
| `Fixtures/` | Golden conformance corpus |
| `examples/` | Apps that mix generated and hand-written code, per platform |
| `bench/` | Performance comparisons |
| `docs/` | Goals, rules, architecture, subset, performance, adoption, lessons |
| `scripts/` | Hooks, privacy scan, repository checks |

## IR and generator boundaries (resolved)

Open decision 1 is resolved by the following initial contract. The IR is a typed, platform-neutral, `Sendable`
value tree: `Module` contains ordered `Screen` values; each screen owns state declarations and a root `ViewNode`.
`ViewNode` has typed cases for stacks, text, buttons, native components, and conditional branches rather than raw
Swift syntax or backend strings. Expressions distinguish literals, localized string keys, references, and bindings.
State declarations preserve local, parent-owned, and model-owned data. Source locations use one-based UTF-8 line and
column coordinates and do not depend on SwiftSyntax.

The frontend exposes `Frontend.parse(SourceFile) -> TranslationUnit`; it returns the IR and ordered diagnostics
without writing files. Each backend exposes `generate(module:mapping:) throws -> String` and consumes the resolved
`Mapping`. An unsupported IR node throws `Diagnostic` instead of emitting a placeholder. Backend-specific lowering
and validation belong in separate backend files; feature-specific IR declarations can likewise be added in separate
files without changing module dependencies.

Diagnostics have stable string codes, a severity, an explanation, an optional concrete alternative, and a source
location. Their golden text is `file:line:column: error [code]: message Suggestion: alternative`. An absent
suggestion omits that suffix. Codes are API: changing one is an intentional fixture and compatibility change.

The initial parser deliberately supports only `VStack`, `HStack`, `Text`, and string-title `Button` with an empty
action. Other IR cases define the next typed boundaries and are not a claim that those features already parse or
generate. New views and expressions extend these types with explicit ownership and source locations; no backend may
introduce a second Swift parser.

## Open decisions

1. **Resolved:** see "IR and generator boundaries" above.
2. **Resolved:** `refract.json` uses the versioned JSON Schema and typed records in `docs/mapping.md`. Native views
   declare their cross-platform stored-property signature in Swift with `RefractNativeView`; the mapping owns the
   per-platform native symbols and typed argument bindings. An explicitly versioned native-only draft is normalized
   for compatibility, but the canonical full mapping keeps separate per-platform component and native-component
   registries. No runtime lookup or target-code template is allowed.

3. **Resolved:** Compose model properties expose `State<T>`; ArkUI uses V2 `@ObservedV2`/`@Trace` implementations
   with `@ComponentV2`/`@Param` inputs, at API 12 or later. No generated observation adapter; see
   `docs/state-and-models.md` for the contract and performance evidence requirements.
4. Which HarmonyOS toolchain can compile generated ArkTS in CI on Linux.
5. Minimum platform versions: Swift / Xcode, Kotlin / Compose BOM, HarmonyOS API level.
