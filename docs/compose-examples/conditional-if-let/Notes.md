# conditional-if-let

Kotlin's smart cast makes `title` non-null inside `if (title != null)`, so `Text(text = title)` compiles without
`!!`. The shadowing form `if let title = title` collapses to the same Kotlin: there is no reason to introduce a
second name.

When the Swift side binds a *different* name (`if let unwrapped = title`), the emitter emits
`title?.let { unwrapped -> … }` to keep the binding explicit.
