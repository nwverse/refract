# Refract

[English](README.md)

**SwiftUI 只写一份，编译期生成原生的 Jetpack Compose 和 ArkUI。**

Refract 读取用 SwiftUI 子集写的页面，为 Android（Jetpack Compose）和鸿蒙（ArkUI）生成地道、可读的源码。在 iOS 上，同一个文件就是普通的 SwiftUI。Refract 没有运行时：生成的代码就是一位细心的工程师会手写的代码，所以运行速度和手写原生代码完全一样。

> 状态：早期开发中。生成器、子集和示例都在公开开发，见[路线图](docs/roadmap.md)。

## 目标

1. **一份 Swift 代码，多端同步。** 页面只写一次，iOS、Android、鸿蒙保持一致。
2. **性能优先，绝不劣化。** 没有运行时库，没有桥接层，不增加启动开销和包体积。各平台的性能规则内置在生成器里，每次改动都要过基准测试。
3. **编译期代码生成。** 生成的 Kotlin 和 ArkTS 提交进仓库、经过评审、结果确定。不支持的写法在构建时报错，绝不生成近似代码。
4. **渐进式迁移。** 在现有原生 App 里一次迁一个组件或一个页面。生成的页面就是普通的 `@Composable` 函数和 ArkUI `@Component`。随时可以停用 Refract，代码照样留着用。
5. **和原生代码自由混用。** 在 Refract 页面里嵌入手写的原生组件，在原生页面里调用 Refract 组件，并在 Swift 源码里声明各平台的差异（动画、自定义绘制）。

每个目标的细节和检验方式见 [docs/GOALS.md](docs/GOALS.md)。

## 工作原理

```text
Screen.swift（SwiftUI 的 Refract 子集）
 ├── iOS        作为普通 SwiftUI 编译
 └── refract generate（构建时）
      ├── Android    Screen.kt   （Jetpack Compose，使用你的设计系统）
      └── 鸿蒙       Screen.ets  （ArkUI，使用你的设计系统）
```

页面通过 model 协议读取数据，Refract 会把这些协议生成为 Kotlin 和 ArkTS 接口，由你现有的 view model 或共享核心来提供数据。见 [docs/architecture.md](docs/architecture.md)。

## 参与贡献

请先读 [CONTRIBUTING.md](CONTRIBUTING.md)。每个改动都走 issue → 认领 → 分支 → PR 的流程。Agent 遵循 [CLAUDE.md](CLAUDE.md)。

## 许可证

[MIT](LICENSE)
