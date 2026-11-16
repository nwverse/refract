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
- **Compile fixtures under their declared package.** When the canonical corpus's `Expected.kt` says
  `package refract.generated` and references `refract.generated.R.string.<name>`, the Gradle module that compiles
  it must use `namespace = "refract.generated"` so the Android plugin generates the matching `R` class. Compiling
  fixture Kotlin under a different `namespace` produces a `com.example.app.R` class that the fixture cannot see,
  and the gate fails with `unresolved reference R` even when the generated Kotlin is correct.
- **Stage fixture outputs under the module's conventional `src/main/` rather than configuring custom
  `sourceSets`.** AGP 9's library plugin reads `sourceSets.main.java.srcDirs` but does not propagate directories
  added after plugin evaluation to the Kotlin compile task's source list, so `:module:compileDebugKotlin` reports
  `NO-SOURCE` even though `sourceSets.main.java.srcDirs` shows the new directory. Writing the staged files under
  `src/main/java/<package>/` and `src/main/res/values/` and adding those paths to `.gitignore` is deterministic,
  requires no source set surgery, and keeps the regenerate-and-diff step in one script.
- **Merge per-fixture Android resources with a duplicate-name guard.** When each fixture brings its own
  `values/strings.xml`, concatenating them blindly produces duplicate `<string name="...">` declarations and the
  build fails with `Error: Duplicate resources`. The merge script must deduplicate entries with identical values
  and reject entries with conflicting values; silently overriding one fixture's resource with another's hides
  drift between fixtures.
