# Refract's goals

Refract lets a team write a screen once, in a subset of SwiftUI, and ship it as native code on iOS, Android and
HarmonyOS. These five goals define the project. Every design, PR and review is judged against them, and
`docs/SUPER_RULES.md` makes them binding: a change that breaks one is not merged, whatever else it improves.

Each goal says what it means, what it rules out, and how a PR shows it is met.

## 1. One Swift source, every platform in step

**Meaning.** A screen or component is written once, in the Refract subset of SwiftUI. On iOS that file is ordinary
SwiftUI, compiled by the Swift compiler with no Refract dependency. For Android it becomes Jetpack Compose and for
HarmonyOS it becomes ArkUI. A change to the Swift file changes all three.

**Rules out.** Hand-editing generated code; a platform silently dropping part of a screen; per-platform forks of
the same screen that drift apart (a deliberate per-platform difference is goal 5's job and is declared in the source).

**Evidence.** Golden fixtures (input Swift, expected Kotlin, expected ArkTS) in `Fixtures/`; the regenerate-and-diff
check; for screens, paired screenshots of the three platforms from the examples.

## 2. Performance first: never a regression

**Meaning.** Code Refract generates performs at least as well as an equivalent, well-written hand-written
implementation on each platform, and never worse than the code it replaces. There is **no Refract runtime**: the
generated code depends only on the platform SDK and the consuming app's own code (its design system, its models), so
Refract adds no library, no start-up work and no binary size of its own.

The generator encodes each platform's performance rules once (`docs/performance.md`), for example stable keys in
`LazyColumn` and `LazyForEach`, stable or immutable parameters so Compose can skip, narrow state reads, and ArkUI's
fine-grained observation, so every generated screen gets them.

**Rules out.** Runtime interpretation, reflection, bridging layers or virtual view trees between the generated code
and the platform toolkit; "temporarily slower" merges; raising a benchmark baseline to make a regression pass.

**Evidence.** Benchmarks in `bench/` compare generated code with a hand-written reference of the same screen (frame
time p50/p99, recomposition or re-render counts, start-up, memory, binary size) on named devices and builds. A
measured regression beyond run-to-run noise blocks the merge. Emulator and simulator numbers are labelled as such and
never presented as device results.

## 3. Compile-time code generation

**Meaning.** All translation happens at build time. Refract reads Swift with SwiftSyntax, checks it against the
subset, and writes idiomatic, readable Kotlin and ArkTS that a reviewer could have written by hand. Generated files
are committed, carry a "generated, do not edit" header and are reviewed like other code; CI regenerates them and
fails on any difference.

**Rules out.** Code generated at run time; silent fallbacks. A construct Refract cannot translate faithfully is a
build-time diagnostic that names the construct, explains why and suggests the supported alternative or a goal 5
escape hatch.

**Evidence.** Generator unit tests and golden tests; the generated Kotlin and ArkTS compile with each platform's
standard toolchain in the examples; diagnostics tests for rejected constructs.

## 4. Incremental adoption

**Meaning.** An existing native app adopts Refract one component or one screen at a time. A generated screen is a
regular `@Composable` function or ArkUI `@Component`, called from hand-written navigation and code like any other.
Data comes in through declared model interfaces that the app's existing view models implement today and a shared
core can implement later, so adopting Refract never waits for a data-layer rewrite.

**Rules out.** A host container, a whole-app rewrite, a global runtime or initialisation step, or a build that only
works when the whole app uses Refract. Lock-in: if a project stops using Refract, the generated sources it committed
remain ordinary native code it can keep maintaining by hand.

**Evidence.** The examples contain apps that mix hand-written and generated screens; the adoption guide
(`docs/adoption.md`) walks one screen from hand-written to generated and back.

## 5. Mixing with native code

**Meaning.** Refract and hand-written native code mix in both directions, so a team is never blocked by what
Refract does not support yet:

- **Native inside Refract.** A Refract screen can place a native component by name (for example a custom drawing, a
  platform-specific animation, a map or a video player). Each platform implements it by hand; the generator checks
  the declared interface so a missing or mismatched implementation fails the build.
- **Refract inside native.** Generated components are called from hand-written screens like any native component.
- **Per-platform variation.** A single modifier, animation or value can differ per platform in the Swift source, in
  a declared and type-checked form, without forking the screen.

**Rules out.** Escape hatches that bypass type checking or that require runtime lookup; per-platform differences
hidden in generated files.

**Evidence.** Fixtures and examples for each direction; diagnostics tests for a missing or mismatched native
implementation.

## Non-goals

- **Full SwiftUI.** Refract accepts the subset it can translate faithfully, and grows it over time.
- **A renderer or a runtime framework.** Rendering is always the platform's own toolkit.
- **Business logic translation.** Logic lives behind model interfaces: native code, or a shared core such as a Rust
  library that every platform links. Refract generates the interfaces, not the logic.
- **Web**, for now. A later backend needs its own proposal.
