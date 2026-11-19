# Mapping lessons

- **Preserve JSON keys and coordinates before decoding.** `JSONDecoder` alone loses duplicate keys and useful source
  positions. Parse to a source-located tree, validate its structure, and only then decode the typed records. Select
  the same duplicate value a JSON decoder would use during validation so a duplicate version cannot hide a later
  unsupported version; generation is still blocked by the duplicate-key diagnostic.
- **Do not use a host component's parameters to validate its modifiers.** Modifier attributes bind the parameters of
  the corresponding global modifier signature. Perform this second pass after both registries are structurally
  validated.
- **Keep a schema's escaping executable in every consumer.** A regex copied from Swift into JSON needs another layer
  of escaping. Validate the published schema with a standard JSON Schema implementation, and parse the packaged
  resource in Swift tests; inspecting its text alone misses invalid JSON escapes.
- **Normalize resource-root paths before comparing them.** `URL` retains directory trailing slashes, so an apparently
  correct one-component resource root can fail a parent-directory comparison. Compare normalized URL paths, include
  an explicit decode assertion for a newly added mapping field, and test regular files/directories without following
  symlinks. Resource metadata checks must not become arbitrary directory enumeration or asset-content reads.
- **Do not make a complete mapping fixture depend on another worktree.** A compatibility example may be copied into
  a test's string input, but test code must never read another Agent's uncommitted path.
- **Coordinate a shared diagnostic renderer before writing golden errors.** The exact prefix and suggestion wording
  are generator-owned. Derive reviewed diagnostic expectations from the implemented contract, not from an earlier
  issue comment that proposed a different rendering.
- **Render resources, do not embed target expressions in mapping strings.** A `{ "resource": "name" }` declaration
  lets each backend produce its typed `R.color` or `$r` reference. Restrict resolver and symbol references to
  qualified identifiers, and give state arguments explicit Boolean types rather than native interaction-source
  objects whose ownership is unknown.
- **Audit generated imports as native code.** A Kotlin `R` reference needs an import even when the class is in the
  generated package; an external package keeps its qualifier. For ArkUI, `AppInteractionColors.resolve` needs the
  exported `AppInteractionColors` symbol, not an import of the whole member expression. Compile the exact golden
  Kotlin after regeneration; a successful CLI run alone does not catch a stale or malformed import.
- **Report project-reference checks without claiming compilation.** Byte-identical shared Swift files and Xcode
  project references prove source wiring, not SwiftUI type checking. Keep `not verified on macOS` explicit when
  Xcode was not run, and do not let a success message imply otherwise.
