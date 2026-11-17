# SwiftPM consumer build integration

`RefractSwiftPMPlugin` is an opt-in SwiftPM **build-tool** plugin. A consuming iOS
library/application package keeps its shared SwiftUI source in its native target and
adds only the plugin to that target. Refract's CLI and host tool execute on the build
host. No Refract library is a dependency of the application target.

## Bounded configuration

One package-root `refract-swiftpm.json` binds one host target to all of its explicit
inputs and committed output directories:

```json
{
  "schemaVersion": 1,
  "target": "RefractConsumer",
  "sources": ["Sources/RefractConsumer/Hello.swift"],
  "mapping": "Sources/RefractConsumer/refract.json",
  "resourceInputs": [],
  "androidOutput": "Generated/Android",
  "harmonyOutput": "Generated/HarmonyOS"
}
```

The fields have these meanings:

| Field | Contract |
| --- | --- |
| `schemaVersion` | Exactly `1`; malformed or missing required fields fail the build. |
| `target` | The one native source-module target to which this configuration applies. Select it explicitly for command-plugin operations. |
| `sources` | Nonempty package-relative Swift paths with unique base filenames. Each file must also be a source of this target, so the host never compiles a copied screen. |
| `mapping` | Optional package-relative generator mapping. Its Android and HarmonyOS `resources.catalog` files are automatically dependencies. |
| `resourceInputs` | Extra generator-input resources not declared by a mapping catalog; empty by default. Every entry must exist. |
| `androidOutput`, `harmonyOutput` | Package-relative committed native-source directories. They must be outside the host target's source/resource directories. |

Paths use POSIX separators, cannot be absolute or contain `.`/`..`, and cannot
traverse symlinks or resolve outside the package. The bounded slice deliberately
has no file discovery, implicit target selection, recursive output deletion, app
runtime, or configuration of the generator's Swift/IR semantics. Use the normal
mapping schema for those generator settings.

The consuming manifest declares the same minimum macOS version as Refract (currently
macOS 13) and adds the plugin to the native target. Its package dependency resolves
the plugin; it does not add a library dependency:

```swift
.target(
    name: "RefractConsumer",
    plugins: [.plugin(name: "RefractSwiftPMPlugin", package: "refract")]
)
```

`examples/swiftpm-consumer/` is the complete small consumer.

## Tool discovery and reproducibility

Provide a checked-in/versioned Refract CLI for the build host. Set
`REFRACT_EXECUTABLE` to an existing executable, or put `refract` on `PATH`. With no
override, the plugin builds the package's host `RefractCLI` target. An invalid
override fails instead of silently downloading or substituting a tool. #154 owns the
archive, checksum and license contract; this integration consumes only its executable.

The plugin resolves the override while creating commands and passes the absolute
executable path in the build command's environment. This forwarding is required:
SwiftPM's build sandbox does not automatically forward the caller's override to the
command. The separately built `RefractConsumerTool` is a host-only dependency of the
plugin, never of the consuming target.

## Inputs, outputs and ordering

For every declared Swift input, the CLI produces `<basename>.kt` and
`<basename>.ets` in `Android/` and `HarmonyOS/` under SwiftPM's plugin work directory.
The command uses the existing `refract generate` interface; no directory is scanned
for new Swift files and no generated Swift view implementation is produced.

SwiftPM's incremental `buildCommand` declares these read dependencies:

- `refract-swiftpm.json` and every explicit Swift input;
- the optional mapping, both mapped native string catalogs and any `resourceInputs`;
- every committed Kotlin/ArkTS output that exists (missing output also fails the
  command, and may instead fail SwiftPM's earlier missing-input planning check);
- a content-preserved plugin-work manifest of each committed output directory's
  direct `.kt`/`.ets` names and metadata, so newly added or removed unexpected files
  also invalidate the check without rewriting the manifest on no-op builds;
- the host tool and generator executable, so replacing either invalidates the result.

A no-op build runs no generator process. Touching a declared input causes deterministic
regeneration and checking. This is SwiftPM timestamp dependency tracking, not a second
custom cache or daemon.

SwiftPM treats declared `.kt`/`.ets` build-command outputs as possible target resources.
To keep those languages out of the iOS target, the plugin declares only
`RefractBuildAnchor.swift` as an output. It contains exactly one comment and no
runtime declarations. Its compilation orders the host source after generation/checking;
the Kotlin/ArkTS staging paths remain explicit tool arguments inside the writable
plugin work directory.

The ordinary build must leave committed sources unchanged. The host invokes the CLI's
read-only `check` command for the complete input group. That command regenerates in
memory and reports missing, stale and unexpected `.kt`/`.ets` committed files. The
host separately regenerates the staging files, with no second comparison policy.

## Publish and check explicitly

Normal builds do not request package-directory write permission. To update committed
native output deliberately:

```sh
swift package refract-generate --target <target> --allow-writing-to-package-directory
```

This generates in a separate command-plugin work directory and writes only the
configured per-input Kotlin/ArkTS files. Review and commit the resulting native
source; generated code remains ordinary platform code if Refract is later removed.

For a read-only check:

```sh
swift package refract-check --target <target>
```

The check command is a separate plugin with no package-directory write permission. A
stale or missing file fails instead of being repaired silently.

## Verification and limits

After building the repository CLI, run:

```sh
python3 -I scripts/test_swiftpm_consumer.py
```

The test uses a clean temporary consumer and the real SwiftPM plugin. It verifies
staged generation, deterministic outputs, zero generator invocation on a no-op build,
invalidation after each declared input changes, missing/stale/unexpected-output
failure, explicit publication, invalid executable diagnostics and symlink boundary
rejection. On Linux
it supplies an isolated syntax-only `SwiftUI` target solely to compile the host
syntax; this is not a SwiftUI implementation or iOS evidence.

A SwiftPM package is not an Xcode `.xcodeproj` iOS application. Real iOS app
compilation, native SwiftUI type checking and visual verification belong to
`examples/ios/` and #150. Kotlin and ArkTS are not compiled by this SwiftPM plugin;
Android and HarmonyOS native builds remain separate checks. No device, performance,
Xcode-project or application-store claim is made by this integration.
