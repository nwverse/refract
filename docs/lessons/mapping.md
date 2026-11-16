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
- **Do not make a complete mapping fixture depend on another worktree.** A compatibility example may be copied into
  a test's string input, but test code must never read another Agent's uncommitted path.
- **Coordinate a shared diagnostic renderer before writing golden errors.** The exact prefix and suggestion wording
  are generator-owned. Derive reviewed diagnostic expectations from the implemented contract, not from an earlier
  issue comment that proposed a different rendering.
