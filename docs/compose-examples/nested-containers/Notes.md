# nested-containers

`.foregroundColor(.secondary)` maps to `MaterialTheme.colorScheme.onSurfaceVariant`: that is the Material 3 role
for secondary text. Projects that use a custom design system override this in `refract.json` (#6).

The inner `Row` does not receive a `modifier = modifier` parameter: only the outermost container of a screen
takes the call-site modifier. Inner containers get `Modifier` (default) unless the Swift side attaches modifiers
to them.
