# Local CLI packages

The release path produces local host tools only. It never publishes an archive, downloads an executable during a
consumer build, or adds Refract to an application's runtime. Generated Kotlin, ArkTS and iOS SwiftUI behavior are
unchanged by packaging.

## Contract

- The package version is `0.1.0`. It identifies an early development contract, not production readiness.
- `refract --version` (or `refract version`) prints the version and full source commit. A source-checkout build
  without a stamped revision reports `unknown-source-revision`; a package always stamps its exact commit.
- Consumer integrations first use the executable file named by `REFRACT_EXECUTABLE`, then search `PATH` for
  `refract`. A configured absolute path must come from the consumer's own environment; the package contains no
  machine-specific path. Integration code must diagnose a missing or non-executable tool rather than silently
  downloading or skipping generation.
- The CLI archives are native `linux-x86_64`, `linux-arm64`, `macos-x86_64` or `macos-arm64` packages. Only the
  current host is built. No cross compilation, universal macOS binary, code signing, notarization or unverified
  platform support is implied.
- The Linux CLI statically links the Swift runtime. System C/C++ libraries remain host requirements, so this is
  not a claim that one Linux binary supports every distribution. The verified Debian 12 build dynamically links
  glibc, libstdc++, libgcc_s, libxml2, ICU 72, zlib and liblzma. macOS uses the system-provided Swift runtime.
  There is no Refract runtime in a generated application on either platform.

## Build from a committed revision

Use Swift 6.4.2, git, Python 3.11 or newer and the platform's `strip` tool on `PATH`. The Swift toolchain is a
build prerequisite, not something the packaging script installs. `Package.resolved` pins the complete direct and
transitive source dependency graph; `scripts/release/third_party_notices.json` pins each corresponding license and
its SHA-256. A dependency update must update both files and copy the exact license from the pinned revision.

From the repository root:

```sh
swift --version
git status --short
git rev-parse HEAD
python3 scripts/package_cli.py --output /tmp/refract-artifacts --verify-reproducible
```

`--revision` accepts a full 40-character commit; the default is the current `HEAD`. The output must be a new or
empty directory outside the checkout. The script fails on a different toolchain, an unresolved commit, stale
licenses or an unsafe destination. It does not use the working tree's uncommitted files.

The command creates:

- `refract-0.1.0-<os>-<arch>.tar.gz`, with `bin/refract` and `lib/refract_RefractMapping.bundle/` beside it.
- `refract-source-0.1.0-<commit>.tar.gz`, containing exactly the selected commit except for its stamped
  `Version.swift` revision. No `.build`, worktree or ignored file is copied.
- A `<archive>.sha256` for each archive. These are integrity checksums for local transfer, not signatures or a
  remote trust anchor.

The binary archive includes `LICENSE`, `THIRD-PARTY-NOTICES.txt`, `BUILD-INFO.json`, and the source manifest and
lockfile. `BUILD-INFO.json` records the source revision, host triple, toolchain and build flags; it deliberately
contains no user, hostname, timestamps or local paths. Archive entries have sorted names, normalized permissions,
zero uid/gid, empty owner names and a zero timestamp. The executable is stripped of debug information before
packaging, so temporary build paths are not distributed in DWARF data.

`--verify-reproducible` makes two independent builds from separately extracted clean source archives and compares
the complete binary archives byte for byte. This proves reproducibility only for the same source revision, host
architecture, OS and toolchain; it is not a cross-toolchain equivalence claim. Without the flag, one clean build
still runs all package validation but makes no two-build comparison.

## Inspect and use a package

Use a new empty directory for an archive; it is untrusted input until its expected checksum is known. Compare the
checksum supplied by the local builder rather than accepting an arbitrary archive and checksum together:

```sh
mkdir -p /tmp/refract-installed
sha256sum --check --strict /tmp/refract-artifacts/refract-0.1.0-linux-x86_64.tar.gz.sha256
tar -tzf /tmp/refract-artifacts/refract-0.1.0-linux-x86_64.tar.gz
tar -xzf /tmp/refract-artifacts/refract-0.1.0-linux-x86_64.tar.gz -C /tmp/refract-installed
REFRACT_EXECUTABLE=/tmp/refract-installed/refract-0.1.0-linux-x86_64/bin/refract
"$REFRACT_EXECUTABLE" --version
"$REFRACT_EXECUTABLE" check --input <screen.swift>
```

Keep `lib/` beside `bin/` when moving the executable: `Bundle.module` resolves its resource bundle relative to
the executable. Do not copy only the binary. `check` never writes native outputs; `generate` needs explicit output
directories or the project's mapping configuration.

For Linux CI, extract the archive into `$RUNNER_TEMP` and pass its executable through `REFRACT_EXECUTABLE`; on
macOS, `shasum -a 256 --check` is the checksum equivalent. CI executes the archive produced by its exact checkout,
not a downloaded release. This repository does not create releases, credentials or external artifact storage.

## Verification and limits

```sh
python3 -I scripts/test/test_package_cli.py
REFRACT_PACKAGE_E2E=1 python3 -I scripts/test/test_package_cli.py
```

The offline tests cover canonical tar metadata, version stamping, source selection and dependency/license pinning.
The opt-in end-to-end test invokes two real clean builds. `REFRACT_PACKAGE_OUTPUT` can name a persistent artifact
directory outside the checkout for later checksum and extraction inspection; by default the test uses a temporary
directory. On every supported CI host, the release job performs the same archive creation, checksum verification,
relocated `--version` invocation and generation smoke test. Linux and macOS each test only their own native package;
neither job claims to validate the other operating system. Android, HarmonyOS and iOS applications still require
their existing toolchain verification; this CLI package is not device, rendering or performance evidence.
