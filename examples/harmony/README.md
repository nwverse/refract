# HarmonyOS mixed-code example

The Stage-model app keeps `EntryAbility`, both routes and `NativeProfile` hand-written. `GeneratedProfile` imports
and calls the generated `Hello` and full `SettingsScreen` components directly. There is no Refract library, second
application entry point, runtime registry or observation adapter.

`entry/src/main/ets/generated/SettingsScreen.ets` is actual output from the canonical shared settings source. The
hand-written `AppSettingsModel` is `@ObservedV2` with `@Trace title`; the page owns model, binding and
`useGeneratedSettings`. `HandWrittenSettingsScreen` uses the same `@Param`/`@Event` contract for rollback.

## Toolchain: authorized SDK acquisition is still a blocker

**This project has not been compiled: no authorized HarmonyOS SDK or command-line compiler was found in the
investigated local environments.** A read-only review of a separate application's `devecocli` workflow established
the command pattern, not a passing compiler or usable local installation. No account was created, no download
agreement was accepted, and no credentials or signing files were read or copied; the other application's environment
was not changed.

Read [the toolchain investigation and exact blocker](../../docs/harmony-toolchain.md) before building. It separates
source review from native compiler evidence and includes the non-installing preflight, app and native-test commands.

Use Huawei's official **Command Line Tools**, not an OpenHarmony source-tree build or a hand-invoked packing JAR.
The official CI guide supports CLI application builds on Linux and macOS. Linux must be 64-bit with glibc 2.28 or
later. The current documented Command Line Tools 26.0.0+ requires JDK 21; older releases may use JDK 17. On
Debian/Ubuntu, the texture-compression tools additionally need the `libgl1-mesa-dev` system package.

Official documentation:

- [Command Line Tools acquisition](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-commandline-get)
- [Command Line Tools download center](https://developer.huawei.com/consumer/en/download/command-line-tools-for-hmos)
- [CI builds and platform requirements](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-command-line-building-app)
- [hvigor command reference](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-hvigor-commandline)
- [Project structure](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-project-structure)

### Acquisition steps that require the developer

1. Open the download center interactively and select the **Linux x86_64** or **macOS architecture-matching** Command
   Line Tools package. The project targets the 26.0.0 SDK configuration. Review any applicable terms yourself. The
   public documentation does not establish an anonymous, scriptable download endpoint; an unauthenticated metadata
   request in this environment required login state. Do not bypass that requirement.
2. Verify the archive using the SHA-256 published with the selected package, then unpack it outside this repository.
   Record the exact selected version and its verified checksum in your local build notes. Do not invent a checksum
   from an unrelated package version.
3. Point `COMMANDLINE_TOOL_DIR` at the unpacked parent containing `command-line-tools`, and use a compatible JDK 21:

   ```sh
   export JAVA_HOME=/path/to/jdk21
   export COMMANDLINE_TOOL_DIR=/path/to/tools
   export PATH="$JAVA_HOME/bin:$PATH"
   export PATH="$COMMANDLINE_TOOL_DIR/command-line-tools/tool/node/bin:$PATH"
   export PATH="$COMMANDLINE_TOOL_DIR/command-line-tools/bin:$PATH"
   ```

   Use the bundled Node.js. The matching HarmonyOS SDK must be installed by the selected tools. `compatibleSdkVersion`
   is `"26.0.0"` and `runtimeOS` is `"HarmonyOS"`; `compileSdkVersion` is omitted so that installed SDK is used.
   `modelVersion` must match the selected Command Line Tools release. `@ComponentV2` itself requires API 12+, but
   this example's build configuration intentionally tracks one current toolchain instead of promising untested SDK
   combinations.

4. If external packages are needed, configure the public registries without disabling TLS verification:

   ```sh
   npm config set "@ohos:registry" https://repo.harmonyos.com/npm/
   ohpm config set registry https://ohpm.openharmony.cn/ohpm/
   ```

### Build after the authorized toolchain is available

The checked-in native `ohosTest` target imports the real generated `SettingsModel` and tests a typed native model
implementation. **The target and its Hypium dependency are source-prepared only, not compiled or executed.** The
source-reviewed dependency record pins Hypium 1.0.25 with its public package URL and SHA-512 integrity. It is not an
OHPM-generated lockfile; authorized `ohpm install --all` must regenerate and verify it.

From the repository root:

```sh
swift build
python3 scripts/check_examples.py
python3 scripts/check_harmony_toolchain.py --check-only
python3 scripts/check_harmony_toolchain.py
python3 scripts/check_harmony_toolchain.py --native-test-target
```

The preflight exits nonzero with the explicit blocker if no authorized tools are installed. It does not install
packages, change configuration or accept terms. Its two build invocations select `devecocli build` and
`devecocli build --modules entry@ohosTest`, respectively, with `examples/harmony/` as the working directory.

If dependency installation is needed, follow the toolchain guide before running `ohpm install --all` from this
directory. Do not present a successful OHPM resolution, JSON validation or TypeScript syntax check as ArkTS
compilation.

The documented hvigor application-build alternative is:

```sh
ohpm install --all
hvigorw clean --no-daemon
hvigorw assembleHap --mode module \
  -p product=default -p buildMode=debug --no-daemon
```

The native test's Stage runner and its unexecuted command are recorded in the toolchain guide. The documented output
pattern is `entry/build/default/outputs/default/*.hap`. With no signing configuration, the
expected artifact is an unsigned HAP, but **that packaging has not been run here**. This repository intentionally
contains no signing certificate, profile, key or password.

Unsigned HAPs are for compile/package verification, not installation. To install on a device, use the official signing
workflow to obtain your `.p12`, `.cer` and `.p7b` materials and configure signing locally. Automatic signing and
debug-profile setup may require login and device registration; never commit those materials. Device screenshots and
performance measurements are also not available for this example.

## Generation and adoption

Generate the same screen for both native apps from the repository root:

```sh
refract generate \
  --input examples/shared/Hello.swift \
  --input examples/shared/SettingsScreen.swift \
  --mapping examples/refract.json \
  --android-out examples/android/app/src/main/java/refract/generated \
  --harmony-out examples/harmony/entry/src/main/ets/generated
```

The generated files include `Hello.kt`/`Hello.ets` and `SettingsScreen.kt`/`SettingsScreen.ets`; compare their bodies
with the canonical fixture apart from the source-name header. The full settings adoption
walkthrough and rollback are in `../../docs/adoption.md`.
