# Refract

[简体中文](README.zh-CN.md)

**Write SwiftUI once. Ship native Jetpack Compose and ArkUI, generated at compile time.**

Refract reads screens written in a subset of SwiftUI and generates idiomatic, readable source for Android (Jetpack
Compose) and HarmonyOS (ArkUI). On iOS the same file is ordinary SwiftUI. There is no Refract runtime: the generated
code is what a careful engineer would write by hand, so it runs exactly as fast as hand-written native code.

> Status: early development. The generator, the subset and the examples are being built in the open; see
> [the roadmap](docs/roadmap.md).

## Goals

1. **One Swift source, every platform in step.** Write a screen once; iOS, Android and HarmonyOS stay in sync.
2. **Performance first, never a regression.** No runtime library, no bridging, no added start-up work or binary size.
   Platform performance rules are built into the generator, and benchmarks gate every change.
3. **Compile-time code generation.** Generated Kotlin and ArkTS are committed, reviewed and deterministic. Unsupported
   input is a build-time diagnostic, never approximate code.
4. **Incremental adoption.** Adopt one component or one screen at a time inside an existing native app. Generated
   screens are plain `@Composable` functions and ArkUI `@Component`s. Stop using Refract at any time and keep the code.
5. **Mix freely with native code.** Embed hand-written native components in Refract screens, call Refract components
   from native screens, and declare per-platform differences (animations, custom drawing) in the Swift source.

The details, and how each goal is checked, are in [docs/GOALS.md](docs/GOALS.md).

## How it works

```text
Screen.swift (Refract subset of SwiftUI)
 ├── iOS        compiled as ordinary SwiftUI
 └── refract generate (build time)
      ├── Android    Screen.kt   (Jetpack Compose, your design system)
      └── HarmonyOS  Screen.ets  (ArkUI, your design system)
```

Screens read data through model protocols that Refract turns into Kotlin and ArkTS interfaces, so your existing view
models, or a shared core, supply the data. See [docs/architecture.md](docs/architecture.md).

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Every change goes issue → claim → branch → PR. Agents follow
[CLAUDE.md](CLAUDE.md).

## License

[MIT](LICENSE)
