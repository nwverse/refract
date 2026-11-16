# Repository tooling lessons

- **Test a repository scanner in temporary git repositories.** Replace its home, private-word configuration and git
  configuration, and use synthetic values. Running tests directly on a public checkout can read machine-specific
  rules and accidentally print a value in a test failure.
- **Redact path diagnostics as well as file contents.** A private value in a filename is still private when the
  scanner reports it. Test that a rejected report contains the rule and location but not the triggering value.
- **Bootstrap dependencies must become real checks.** A prerequisite gate must be centralized, documented and
  removed by the end of its owning issue. It must not turn into a per-file exemption in the checker.
- **Treat downloaded lint tools as untrusted input.** Extract one named binary into a fresh temporary directory,
  verify the release archive checksum before extraction, and execute it from the repository rather than from the
  download directory.
- **Pin every external tool an Android compile gate downloads.** Record the SHA-256 of the Android command-line
  tools zip directly in the workflow next to its download URL and pass it through `sha256sum --check --strict`
  before extraction; the Gradle wrapper already pins its distribution with `distributionSha256Sum`. Mirror every
  version pin (compileSdk, build-tools, AGP, Kotlin plugin, Compose BOM, JDK) into `examples/android/README.md`
  and the Gradle build scripts so a stale doc value fails the regenerate-and-diff check rather than silently
  drifting from CI.
- **Keep compile gates compile-only.** A CI job that compiles generated Kotlin must not be read as evidence for
  runtime behavior, device performance or visual parity. State that limitation in `docs/ci.md` and the example
  README, and leave emulator/device or HarmonyOS gaps as their own issues instead of being hidden by the new gate.
- **Treat the Gradle cache as an optimization, not a correctness dependency.** Key `actions/cache` by the wrapper
  properties and Gradle build scripts and restore with `restore-keys`. The compile must still succeed from an
  empty cache; never let a CI job depend on a warm cache to download a pinned toolchain, and never let a pull
  request write a shared cache that a subsequent build treats as authoritative.
