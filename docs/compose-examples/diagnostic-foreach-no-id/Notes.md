# diagnostic-foreach-no-id

`LazyColumn` needs a stable `key` per row to preserve scroll position and row state across updates. Without an
identity the emitter would have to fall back to positional keys, which break as soon as the data is reordered.
That is a silent performance regression (goal 2), so the emitter refuses with `RF-C003` and points at the two
supported fixes.

The same rule applies to `ForEach` outside a `List`: positional `ForEach` is allowed only when the collection is
a compile-time constant range (`ForEach(0..<5)`), where position *is* the identity.
