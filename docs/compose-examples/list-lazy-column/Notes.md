# list-lazy-column

`Contact` is declared in the app's own code, not generated: Refract only references it. The IR carries the
`Identifiable` conformance, so the emitter knows to use `key = { it.id }`. `contentType` is the row's static type
name so Compose can recycle composition across rows of the same type (goal 2).

A `List` whose element type is not `Identifiable` and has no explicit `id:` key path is rejected with `RF-C003`:
emitting a keyless `LazyColumn` would silently regress scroll performance and state restoration.
