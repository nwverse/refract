# HarmonyOS toolchain and native build gate

The example targets Huawei Command Line Tools **26.0.0**, the matching HarmonyOS SDK and JDK 21. The
source configuration and acquisition guide were reviewed, but **no HarmonyOS compiler or SDK was found on the
investigated machines**. Neither the generated settings screen nor its native test target has been compiled.
This page is an explicit toolchain blocker, not a successful-build record.

## What the investigation established

- `devecocli`, `ohpm`, `hvigorw` and a HarmonyOS SDK are absent from the local executable path and standard
  installation locations. Read-only inspection of a separate application's `devecocli` workflow found the commands
  `devecocli build` and `devecocli build --modules entry@ohosTest`, but no installed tool or native build output.
  Those commands are source evidence, not compiler evidence.
- The accessible macOS environment also had no DevEco Studio installation in its common application locations or
  file metadata index. No environment was modified and no credentials, signing files or private configuration were
  read or copied.
- Public vendor documentation URLs returned application shells in this environment. The example's acquisition and
  version statements come from its existing source documentation; they have not become independently verified
  download or compiler claims. No anonymous redistributable archive or usable installation checksum was established.
- No account was created, no vendor terms were accepted and no unverified package was downloaded or executed.
  A maintainer must personally authorize acquisition of the official tools. An agent must not bypass a login or
  license prompt.

## Authorization and installation boundary

The developer must use the [official acquisition guide](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-commandline-get)
and [download center](https://developer.huawei.com/consumer/en/download/command-line-tools-for-hmos) to select the
Linux x86_64 Command Line Tools **26.0.0** package and its matching HarmonyOS SDK. Review any applicable account
and license requirements in the developer's own session. Do not put a private download URL, account, token, local
installation path or signing material into the repository or an issue.

Verify the archive against the SHA-256 displayed for that exact package before unpacking it outside the checkout.
Use a fresh empty directory for the download and extraction, keep other scripts outside that directory, and do not
run an interpreter from an untrusted extracted directory. Record the version, publisher checksum and license review
in private local notes. No matching verified checksum is currently available here, so there is no reproducible
scripted installation to publish.

The [CI build guide](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-command-line-building-app)
and [hvigor command reference](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-hvigor-commandline)
are the authoritative command documentation. The local host meets the documented 64-bit Linux, glibc 2.28+ and JDK
21 prerequisites; that does not establish SDK compatibility or compilation. Install any operating-system library
requested by the vendor guide through the normal administrator-managed process, not by changing a shared machine
from this repository's scripts.

Set `COMMANDLINE_TOOL_DIR` to the parent containing `command-line-tools`, and use JDK 21:

```sh
export JAVA_HOME=/path/to/jdk21
export COMMANDLINE_TOOL_DIR=/path/to/tools
export PATH="$JAVA_HOME/bin:$PATH"
export PATH="$COMMANDLINE_TOOL_DIR/command-line-tools/tool/node/bin:$PATH"
export PATH="$COMMANDLINE_TOOL_DIR/command-line-tools/bin:$PATH"
```

Keep these machine-specific values in local configuration, not committed files. The repository contains no signing
certificate, profile, private key or password.

## Compile the real generated source, then its native test target

From the repository root, first establish that the committed settings `.ets` is unchanged actual CLI output:

```sh
swift build
python3 scripts/check_examples.py
python3 scripts/check_harmony_toolchain.py --check-only
```

The preflight only locates existing executables. It never installs packages, changes npm/OHPM configuration,
accepts licenses, reads credentials or treats a syntactic TypeScript check as ArkTS compilation. Run the explicitly
authorized `ohpm install --all` step below before building when dependencies are not already resolved.

Build the application and native test target in two separate invocations:

```sh
python3 scripts/check_harmony_toolchain.py
python3 scripts/check_harmony_toolchain.py --native-test-target
```

The wrapper calls `devecocli build` from `examples/harmony/`; `--native-test-target` adds `--modules entry@ohosTest`.
Its vendor stdout and stderr are passed through unchanged. Preserve the full command, tool version, selected SDK,
exit status and resulting artifact hash with the verification report. The application build compiles the actual
`generated/SettingsScreen.ets`; the native test also checks a small typed model implementation against its
`SettingsModel` interface.

The test source imports `SettingsModel` and constructs a typed implementation whose `title` and `save()` are checked
with Hypium. This is a native API/contract test, not an automated rendering, accessibility, lifecycle or performance
claim. The checked-in `ohosTest` target is prepared from the source-level DevEco workflow pattern; **its SDK imports,
module manifest, test runner and application sources all remain uncompiled until the authorized toolchain runs**.

`ohpm install --all` is required before the native build because the selected vendor distribution has not resolved
Hypium locally. Run it from `examples/harmony/` only after the developer has approved the official public registry
and package license requirements. `oh-package.json5` pins `@ohos/hypium` 1.0.25, and the source-reviewed
`oh-package-lock.json5` records the corresponding public package URL and SHA-512 integrity in a simple readable
form. It is **not an OHPM-generated lockfile**: no package installation was performed here, and OHPM compatibility is
unverified. Let OHPM regenerate that metadata, inspect its dependency and integrity diff, and do not call resolution
success a compiler pass.

If the installed distribution does not expose `devecocli`, the equivalent documented application build from
`examples/harmony/` is:

```sh
hvigorw clean --no-daemon
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

Use the matching documented `ohosTest` target command rather than substituting a normal HAP for test evidence. A
nonzero compiler exit is a native compatibility issue to fix, not permission to replace the generated source with a
stand-in or to report success based on golden files.

## Execution, signing and evidence remain separate

An unsigned HAP is compile/package evidence only. Installing it or an `ohosTest` HAP needs the official signing
workflow, a dedicated emulator/device and its serial. For the example bundle, an authorized installed test target
can use this Stage runner command with the appropriate module/test configuration:

```sh
hdc -t '<device serial>' shell aa test -b com.example.refract -m entry_test \
  -s unittest OpenHarmonyTestRunner -w 60
```

No device, emulator, `hdc`, rendering or performance result was obtained. Do not launch or reset a shared device
without ownership coordination. Keep signing secrets and device captures out of the repository; record separately
whether the evidence is compile-only, an emulator run or a physical-device run.

Issue #166's [native rendering host and runner](../examples/harmony/verification/README.md) uses this preflight and
build path, then adds explicit target selection, native UI behavior, theme capture and evidence checks. It is also
source-prepared only. The runner requires an already allocated target and authorized signing; it does not expand
this document's acquisition permissions or close the rendering blocker.

Once the missing authorized SDK is supplied, issue #151's remaining verification steps are to run the two builds,
resolve any actual ArkTS diagnostics, and only then enable a self-hosted or otherwise licensed CI gate. A hosted
compile job without a documented licensed tool distribution is not a substitute.
