# HarmonyOS paired benchmark: source-prepared, not executed

## Explicit blocker

There is no authorized HarmonyOS compiler, SDK, `hdc`, signing configuration or execution target in the available
environment. This issue did not create an account, accept vendor terms, bypass a login or download an unverified
package. **No ArkTS compilation, application execution, screenshot, memory measurement, binary measurement or timing
is claimed.** Source-level references here must not be promoted to device evidence.

The prerequisites and official acquisition boundary are in [the toolchain guide](../../docs/harmony-toolchain.md).
The developer must personally obtain and verify the authorized Command Line Tools and matching SDK, then provision a
signed, explicitly owned target. Do not commit credentials, signing material, machine-local paths or private URLs.

## Source sharing with #166

This directory is independent of `examples/harmony/`. Issue #166 retains rendering ownership for the unchanged real
settings example; this issue adds no rendering PR or capture claim. The benchmark's generated screen comes from the
existing canonical `bench/android/SettingsScreen.swift`, shared with Android and iOS, not from #166's settings screen.

```sh
swift build
python3 -I bench/harmony/generate.py --check
```

`refract.json` retains the Android mapping/resource paths from the shared benchmark and overrides only the HarmonyOS
token import to the app-owned native typography module. The source and native resource catalogs remain unchanged;
`generate.py --check` invokes the real CLI and byte-compares the generated file without editing it. A regeneration
without `--check` updates only the reviewed benchmark ArkTS output, never #166's example.

`entry/src/main/ets/generated/SettingsScreen.ets` is actual CLI output, with the reviewed generated header. The mapping
imports `AppTypography` from the app-owned `../native/AppTypography` module; its exact module and `Font` typing still
needs a native compiler pass. The handwritten
`ReferenceSettingsScreen.ets` does not call the generated row. Both use the same 200-row `@ObservedV2` model and typed
`BasicDataSource<SettingRow>`, stable identity, the same `setting` reuse identity and immutable row replacement with
`notifyDataChange(index)`.

These files are source-prepared only: project/build manifests, entry ability, native page, typography and independent
reference. Their exact ArkUI APIs, decorator semantics, build configuration and module imports have **not** been
accepted by a vendor compiler. Do not hide a compiler diagnostic by deleting observation, switching to a non-lazy list,
dropping accessibility or editing generated output independently of the canonical source.

## Required execution after authorization

1. Regenerate and review both generated backends. Compile the unchanged generated ArkTS and native reference with the
   matching authorized toolchain in Release mode. Record tool/SDK/JDK versions, full source revision and exact command.
2. Use two ordinary native entry points, not a runtime interpreter. Drive identical cold launch, programmatic scroll
   and eight-toggle local-update scripts for 30 iterations each. Ensure both variants expose the same rows, controls,
   accessibility and lifecycle. Do not time a button callback or a shell command as UI rendering.
3. Record native launch-to-first-frame, frame duration, component render/reuse counters and resident memory with the
   vendor profiler and its documented export. Capture one distinct raw trace per variant/scenario/iteration, with the
   exact `hdc` serial, OS build, device/emulator classification and build configuration.
4. Measure the final installed artifact's bytes, not a source or temporary build directory. Keep memory and binary size
   as positive integer bytes. Do not compare an Android frame metric with a HarmonyOS frame metric across targets.
5. Normalize with `python3 -I bench/common/report.py <run>/manifest.json --output <new-report-directory>`. The
   HarmonyOS manifest must reference `vendor-trace` and `vendor-metric-json` artifacts; iOS `.trace` files cannot be
   relabelled as HarmonyOS evidence. Missing pairs, unbound samples, incomplete iterations or checksum errors fail.

The following are **unexecuted placeholders**, not verified vendor command syntax or a working runner:

```sh
python3 scripts/check_harmony_toolchain.py
hdc -t '<owned-serial>' shell aa force-stop com.example.refract.bench
hdc -t '<owned-serial>' shell aa start -a EntryAbility -b com.example.refract.bench
# Use the authorized profiler's documented native trace export, not shell elapsed time.
python3 -I bench/common/report.py <run>/manifest.json --output <new-report-directory>
```

Until those prerequisites and execution steps are complete, the issue's allowed outcome is this explicit
toolchain/target blocker with **no performance claim**, not a partial PASS.
