# text-modifiers

`font` and `foregroundColor` become `Text` parameters (`style`, `color`), not `Modifier` entries: that is the
idiomatic Compose split. `padding` is a real modifier and lands on the `Modifier` chain. The default `.padding()`
with no arguments maps to `16.dp`, matching SwiftUI's default padding.

The `style = MaterialTheme.typography.titleLarge` line assumes the default Material 3 mapping. A project that
declares a different title style in `refract.json` gets its own token here instead (#6).
