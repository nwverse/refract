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
