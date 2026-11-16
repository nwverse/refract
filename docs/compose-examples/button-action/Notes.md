# button-action

A stored `var onGreet: () -> Void` on the Swift `View` becomes a Kotlin function parameter with the same name.
`Button("Greet") { onGreet() }` collapses to `Button(onClick = onGreet)` because the action body is exactly the
forwarding call — no extra lambda allocation, and `Button` can skip when `onGreet` is stable (goal 2).

When the action body is more than a single forwarding call, the emitter wraps it in `remember(onGreet) { { … } }`
so the lambda identity is stable across recompositions; see `docs/compose-backend.md` "Performance rules".
