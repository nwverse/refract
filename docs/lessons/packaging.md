# Packaging lessons

- **A host CLI needs its SwiftPM resource bundle.** An executable can start without the bundle and then fail to
  load `refract.schema.json`. Keep `lib/refract_RefractMapping.bundle` beside `bin/refract` and run generation
  after relocation, not just `--version` next to the build products. Preserve the bundle's internal structure:
  Linux places the schema at its root, while macOS uses `Contents/Resources/refract.schema.json`. Locate exactly
  one regular schema rather than assuming either layout. Name the smoke-test input and outputs
  explicitly: the CLI names generated files after the input filename, not the Swift view declaration, so
  `Input.swift` produces `Input.kt` and `Input.ets`.
- **Dynamic Swift linkage is not a distributable Linux package.** A development machine's toolchain can satisfy
  `libswiftCore.so` while a consumer's host cannot. Build the Linux CLI with `--static-swift-stdlib` and document
  the remaining system C/C++ library requirements. Do not describe this as a fully static or universal binary.
- **Debug information defeats path-independent reproducibility.** Two clean builds can differ solely because their
  temporary paths are embedded in DWARF. Strip debug information before packaging and compare the entire archives,
  not only generated native text. Swift 6.4.2's driver rejects the documented newer
  `--experimental-strip-products` spelling; invoke GNU `strip --strip-debug` on Linux and Apple `strip -S` on
  macOS. Do not pass `--static-swift-stdlib` on macOS: its Swift runtime is supplied by the OS and the compiler
  rejects static linkage. CI must actually exercise both host tool conventions.
- **A source archive must contain the whole selected commit.** Filtering only Swift and mapping files silently
  omits the packaging tool, licenses and documentation. Use the Git tree, reject symlinks and other non-regular
  entries, and stamp only the source-revision constant. Never infer a release version from a mutable branch name.
- **Dependency pins need corresponding legal pins.** `Package.resolved` identifies source revisions but does not
  include redistribution notices. Keep the exact license and its SHA-256 beside the packaging script and fail when
  either the revision or license file drifts. Read the manifest, lockfile, notice registry, project license and
  third-party licenses from the selected Git commit, not from the working tree. A two-revision fixture with
  deliberately dirty provenance files catches accidental mixing; packaging fails when the selected revision does
  not contain the required evidence. Generated applications do not link the CLI's parser dependency.
- **Reproducibility and portability are different claims.** Byte-identical archives from two clean builds on one
  host say nothing about other operating systems, architectures or Swift releases. Record the exact host triple
  and toolchain in `BUILD-INFO.json` and avoid general compatibility claims without separate evidence.
