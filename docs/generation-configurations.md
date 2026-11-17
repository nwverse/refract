# Consumer generation configurations

A consuming Android application can keep debug, internal and release native source under separate roots. All three
configurations use the same explicit Swift inputs, mapping, resource catalogs and versioned CLI. They do **not** change
the Swift/IR semantics or insert a runtime switch. The resulting Kotlin and ArkTS are therefore byte-identical when
their inputs and generator are identical.

The `dev.refract.generator` plugin is a repository-local, build-only integration. It does not download a generator,
add an application dependency or read an environment variable that selects production UI. `REFRACT_CLI_PATH` supplies
an existing executable, and `REFRACT_REQUIRED_VERSION` (or `refract.requiredVersion`) pins its complete
`refract --version` output. A packaged CLI includes the source revision, while an unversioned local development build
reports `unknown-source-revision`; the consumer pins whichever complete identity it deliberately selected.
Generation, checking and explicit publication all stop before writing when it does not match. See `packaging.md` for
versioned source packages.

## Declare the shared inputs and each output root

```kotlin
refract {
    executable.set(providers.environmentVariable("REFRACT_CLI_PATH").map {
        layout.projectDirectory.file(it)
    })
    requiredVersion.set(providers.environmentVariable("REFRACT_REQUIRED_VERSION"))

    sources.register("screens") {
        inputs.from(
            layout.projectDirectory.file("swift/Hello.swift"),
            layout.projectDirectory.file("swift/Settings.swift"),
        )
        mapping.set(layout.projectDirectory.file("refract.json"))
        resources.from(
            layout.projectDirectory.file("res/values/strings.xml"),
            layout.projectDirectory.file("harmony/string.json"),
        )
    }

    for (name in listOf("debug", "internal", "release")) {
        configurations.register(name) {
            androidVariant.set(name)
            androidOutputDirectory.set(layout.projectDirectory.dir("generated/$name"))
            harmonyOutputDirectory.set(layout.projectDirectory.dir("generated/$name"))
        }
    }
}

android {
    buildTypes {
        create("internal") {
            initWith(getByName("debug"))
        }
    }
}
```

A configuration name begins with a lowercase ASCII letter and contains only ASCII letters and digits. Every Android
variant selects exactly one configuration through `androidVariant`; missing or duplicate bindings fail at
configuration time. There is no inference from a build environment. If a consumer declares no configurations,
single-source-group consumers retain the existing debug/release production defaults: Kotlin below
`refract/generated/<group>/` and ArkTS below `refract/generated/<group>/harmony/`.
Declaring an `internal` configuration is opt-in and leaves those defaults untouched. Every explicitly declared
configuration must set its output roots; except for the legacy debug/release pair, different configurations cannot
share a reviewed root. Each source group receives a separate `<root>/<group>/android/` and
`<root>/<group>/harmony/` directory so that the complete-output check has an unambiguous owner.

The output directories are per configuration **and per complete source group**. Each independently mapped source
group has its own child directory. Do not hand-edit the group directories to merge configurations: the checker must
own the complete input set for each directory. This preserves the shared input-group contract from #156 rather than
adding a second mapping language.

## Generate, compile, check and publish

- `generate<Variant>Refract` invokes the real CLI for both native backends into separate, build-owned Android and
  HarmonyOS staging roots below `build/generated/refract/<configuration>/<group>/`. Android compilation receives
  only that variant's generated Kotlin through `addGeneratedSourceDirectory`. `compileInternalKotlin` is therefore
  a normal consumer build, not a custom compiler path.
- `check<Variant>Refract` invokes #164's real `refract check` with the same inputs, mapping and explicit reviewed
  roots. Missing, stale or extra Kotlin/ArkTS files fail without writing either directory. `checkRefract` covers
  every bound Android variant.
- `publish<Variant>Refract` is the explicit source-publication operation. It first validates the complete dual-backend
  output in build staging, then invokes the CLI's own locked, rollback-capable output writer for the reviewed roots.
  Normal generation, checking and application builds never modify these reviewed files. Unrelated files in a
  publication root are rejected rather than silently removed. Publication is per complete source group and is not a
  cross-directory atomic filesystem transaction; wait for the command to finish before reviewing or committing.
- `verifyRefractVersion` runs before every operation and records the matched version under the build directory. An
  explicit path alone is not version evidence.

For the example above:

```sh
export REFRACT_CLI_PATH=<existing-refract-executable>
export REFRACT_REQUIRED_VERSION="$($REFRACT_CLI_PATH --version)"
./gradlew clean compileInternalKotlin
./gradlew publishDebugRefract publishInternalRefract publishReleaseRefract
./gradlew checkDebugRefract checkInternalRefract checkReleaseRefract
```

Run publication deliberately, review both native diffs and commit them. A clean build must regenerate and compile
without relying on a previous build directory. Repeating an unchanged generation task reports `UP-TO-DATE`.
Versioned release artifacts retain source and dependency provenance; no opaque binary, binary patch or runtime flag
is used to select an internal screen.

The functional test in `tools/gradle/` creates a real Android application, publishes all three configurations, compares
both generated backends byte-for-byte, compiles internal Kotlin and verifies a deliberately stale internal output
fails without modification. These are **source-generation and Kotlin host-compilation results**, not emulator,
device, rendering or performance results. ArkTS is genuinely generated but requires the authorized HarmonyOS compiler
for native compilation. iOS still compiles the original Swift as ordinary SwiftUI on macOS; no Linux result is iOS
compilation evidence.

If different content is required, express it through the existing typed Swift input/mapping contract and make that
input an explicit build dependency. A generation configuration is only an output and build-variant binding; it is
not a hidden production-content toggle.
