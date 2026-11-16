<!-- English title and body: a squash merge makes them the commit on main. Link the issue with a closing keyword, for example "Fixes #123" (or "Refs #123" to link without closing). -->

## What changed and why



## Verification

<!-- Commands you ran and their results (swift build, swift test, fixture regeneration, example builds, benchmarks).
     Say what was not run and why (a missing toolchain, no device). -->



## Goals self-check

<!-- docs/GOALS.md. Mark each: done (with evidence), not affected, or deviated (deviations are not merged; open an issue). -->

- [ ] 1 One Swift source: no hand-edited generated code; fixtures cover the change on every backend it affects.
- [ ] 2 No performance regression: no runtime library, start-up work or binary size added; benchmark numbers (device or labelled simulator/emulator) when generated code changes shape.
- [ ] 3 Compile-time generation: output is deterministic and committed; unsupported input yields a diagnostic, never approximate code.
- [ ] 4 Incremental adoption: generated code stays callable from hand-written code with no host container or global setup.
- [ ] 5 Mixing with native code: escape hatches stay type-checked; per-platform differences are declared in the Swift source.
