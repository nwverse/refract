# Performance conformance patterns

These cases are hand-written expected native patterns for `docs/performance.md`. They are not a second semantic
subset and do not relax any diagnostic in `docs/subset.md`. Each accepted case has an `Input.swift`, `Expected.kt`
and `Expected.ets`, like the rest of the corpus. The current generator is a skeleton and cannot lower these yet:
backend PRs must make the corresponding golden tests pass and must not mark them generated merely because this
directory exists.

The compiling Android implementation in `bench/android/app/src/main/java/dev/refract/bench/` is the initial
stand-in for the Compose patterns. ArkTS files have been source-reviewed against the linked official documentation,
but have not been compiled because the HarmonyOS command-line SDK is unavailable.

Rules are additive only where their target versions permit: V2 state observation requires API 12, and
`@ReusableV2` requires API 18. Omit reuse for API 12–17; never fall back to V1 decorators.
