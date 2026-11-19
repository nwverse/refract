# Generated-code semantics and compile review (issue #67)

## Scope and evidence boundary

The review began at `67789a2` and merged successive main commits through `1822d1b`. Production code was not edited:
all standalone reproductions used temporary input/output directories, and this PR adds only this report. No shared
IR, manifest or golden expectation was changed. Each final CLI reproduction uses a freshly rebuilt executable;
unit tests do not update the CLI binary, so testing a newly merged commit without `swift build` is not valid.

The review compared the frontend and both emitters with `docs/subset.md`, `docs/state-and-models.md`,
`docs/interop.md` and `docs/architecture.md`. `docs/performance.md` was not present on the reviewed main; its open
PR #44 and the structural state/identity rules were reviewed separately. No benchmark or device claim follows from
this report.

There are two distinct evidence levels:

- **Ready golden regeneration** proves the checked-in expectation equals current generation. It does not itself prove
  that the SwiftUI contract was faithfully translated or that target code compiles.
- **Native compilation** was run for the two generated screens in `examples/android`, not for every ready golden.
  ArkTS and iOS compiler verification was unavailable for the reasons below.

The corpus's documented policy says that accepted goldens are hand-written. Their authoring history and the #2
contract were reviewed, and representative outputs were checked against source semantics. The manifest contains no
machine-readable author/reviewer provenance or native-compilation status per case, so no stronger claim of
independent expert or compiler review is made here. Pending golden files must not be treated as proof that either
backend works.

## Checks performed

| Check | Result and evidence |
| --- | --- |
| Swift 6.4.2 Linux `swift build` | Passed at `67789a2`, `ccd21ce`, `65f0821`, and again after merging `1822d1b` before CLI reproductions. |
| Complete `swift test` | Passed at `67789a2` and `ccd21ce`. At `65f0821`, 85 executed Swift Testing tests passed plus 18 parameterized pending golden placeholders reported as known issues. Pending cases were not counted as passing generation. The final full run is repeated after merging later dependencies. |
| Corpus accounting at `1822d1b` | `Fixtures/Corpus.json` has 58 entries: 40 ready, 18 pending. The 30 canonical v0 cases comprise 13 ready and 17 pending. Loader tests enforce exact manifest/directory matching, required expectation shape, duplicate rejection and deterministic order. |
| Determinism and representative goldens | At `ccd21ce`, ran the CLI twice into separate directories for `hello`, `state-counter`, `model-interface`, `parent-binding`, `compose-typed-layout`, `compose-image`, `v0-scroll-content`, `interop-native-component` and `interop-platform-view`. Both runs and both target outputs were byte-identical to their then-current checked-in goldens. Later localization/state changes are covered by the full golden suite and targeted CLI runs. |
| Generated Android example compilation | `examples/android/gradlew -p examples/android :app:compileDebugKotlin` passed at `a0c0c47` with JDK 17.0.20.1, Android SDK 37.2 and the checked-in Gradle wrapper. This compiles actual generated `Hello.kt` and `NativeComponentScreen.kt` and their native callers; it is not evidence for other golden cases or device behavior. |
| Example regeneration | `python3 -I scripts/check_examples.py` passed: generated Android/Harmony outputs match committed outputs, resource catalogs agree, and the iOS project references shared Swift inputs. |
| Error atomicity | Combined a valid `ValidAtomic.swift` with `Fixtures/rejected-image/Input.swift`. CLI returned non-zero for `RF-C002`; neither requested output directory contained a file. Multiple-input tests also cover this boundary. |
| Public native entry points and interop | Inspected generated Kotlin and ArkTS plus `NativeCaller.kt`/`.ets` and `InteropCallerTests`. Compose exposes ordinary public `@Composable` functions with trailing `Modifier`; ArkUI exports `@ComponentV2`, never `@Entry`. Selected native calls have statically resolved typed arguments/imports. Missing native mapping diagnostics stop both outputs. |
| Runtime/performance structure | `Package.swift` contains generator modules only. Reviewed generated examples import platform/application symbols, with no Refract runtime, registry, reflection, host initialization, generated model mirror or index-key fallback. Compose `State` and ArkUI V2 reads remain at leaves. No device measurement was run. |
| Repository checks | Privacy scan, PR-link tests (41/41) and doc-path self-tests (10/10) passed. The full doc-path run initially reported missing `docs/performance.md` and two mapping fixture paths; those dependencies belong to #9/#6. Final PR verification must rerun the check after they merge, not bypass it. |

## Confirmed defects filed separately

Each issue below has a minimal input, expected behavior, observed CLI result and owning area. Exact issue searches
and open-PR review found no existing issue at the time of filing. Implementation remains with their owners.

| Issue | Confirmed behavior | Minimal proof |
| --- | --- | --- |
| #70 | Swift parser errors are not surfaced. An unterminated `Text(verbatim:)` call exits 0 and generates both targets instead of `RFSYN001`. | Malformed `SyntaxScreen` with a missing closing `)`; both generated files appeared. |
| #72 | Unsupported View member declarations are silently ignored. | `MethodScreen` contains `func unsupportedHelper() {}` and a valid body; CLI exits 0 instead of `RFSYN004`. |
| #73 | Unresolved stack spacing is emitted as an undeclared native identifier. | `VStack(spacing: undefinedValue)` exits 0, producing `undefinedValue.dp` and `this.undefinedValue`. This is distinct from implementing supported token spacing in #65. |
| #74 | ArkUI validates mappings for an unselected iOS native-view branch. | `refractView(ios: AppleBadge, android: AndroidBadge, harmonyOS: HarmonyBadge)` with only generated-target mappings fails on missing `AppleBadge` HarmonyOS mapping. Selected-target mapping checks must remain. |
| #75 | Swift external-label overloads generate duplicate Kotlin method signatures. | `update(_ value: Bool)` and `update(with value: Bool)` both become `update(value: Boolean)`; CLI exits 0 instead of `model.duplicate_member`. |

Coordination notes were posted on #2, #4, #5 and #65. No production fix was made under this review issue.

## Handwritten contract findings and pending coverage

The independent v0 review explicitly looked for dropped Toggle titles, ordered rounded backgrounds, lazy-list
identity/data-source ownership, model observation, resource normalization, root modifiers and non-entry ArkUI
components. Findings:

- `Fixtures/v0-scroll-content/Input.swift:5` omits stack spacing, but
  `Fixtures/v0-scroll-content/Expected.kt:18` inserts `Arrangement.spacedBy(8.dp)`. This contradicts the omitted-
  spacing rule in `docs/lessons/fixtures.md` and the native default contract. It was recorded on #2; #65 already owns
  the typed default/spacing correction, so no duplicate issue was filed.
- After #58 merged, `Fixtures/v0-local-state/Expected.kt:25` still lacks one closing `)` and the Material3 `Text`
  import; `v0-binding-state` has the same malformed localized Text call. Both are marked ready and golden
  regeneration succeeds, proving that a golden match does not imply Kotlin validity. The reproduction matches the
  malformed checked-in Kotlin exactly. #76 was filed by another Agent while this finding was being checked, so #67
  did not duplicate it; #5/#66 own the fix and native compile gate.
- The Toggle ArkUI golden retains its visible localized title, `Blank()` and native change callback. Compose emits
  the same title beside `Switch`, rather than reducing `Toggle` to an unlabeled switch. The syntax defect above
  does not change that semantic finding.
- Several pending handwritten v0 outputs still contain early bare-string output. They must stay pending until the
  localized and typed contract is actually implemented and reviewed. The malformed local-state golden is now merged
  and tracked by #76; it must not be hidden by another expectation rewrite without a native compile check.
- `docs/lessons/arkui.md` still describes generating a data source and synchronizing arrays during appearance,
  whereas the current `docs/subset.md` contract requires an application-owned `IDataSource`/`BasicDataSource`
  boundary with no generated mirror. #63 owns the remaining replacement/toolchain evidence.
- At `1822d1b`, the rebuilt CLI's `v0-identified-list` output matches both hand-written goldens exactly: Compose
  emits `State<List<SettingItem>>`, `@Immutable`, direct `LazyColumn.items`, stable `item.id` and homogeneous
  `contentType`; ArkUI emits `BasicDataSource<SettingItem>`, `LazyForEach`, `ListItem` and a String/Int key path.
  However the manifest still marks it pending. #2/#62 have been notified to coordinate activation and required
  native evidence. This report does not change readiness or claim compilation.
- Modifier ordering and localized titles are represented in the hand-written canonical expectations. Current
  implementation coverage is incomplete and remains pending rather than silently accepting an approximation.

No additional duplicate issue was filed for already-owned or not-yet-ready areas. The absence of a new issue does
not turn a pending contract into verified functionality.

## Areas with no confirmed defect in this pass

- Deterministic generation for the nine representative ready cases at `ccd21ce`.
- CLI accumulation of backend errors before writing output for the tested multi-input rejection.
- Ordinary public native entry points, absence of generated `@Entry`, and native caller imports.
- Explicit native parameter labels/types and selected scalar/view platform alternatives in their covered cases.
- Application-owned scalar model interfaces with leaf-level Compose `State` and ArkUI V2 reads in ready goldens.
- Explicit pending accounting and structural validation; no pending case was silently promoted by this review.
- No generated Refract runtime dependency or startup initialization was found in the inspected outputs.

These are bounded findings, not a claim that all Swift inputs or all target APIs are covered.

## Toolchains and verification still missing

- **ArkTS/HarmonyOS:** no compiler was run. The official Command Line Tools/SDK acquisition documented in
  `examples/harmony/README.md` requires interactive developer access and license review; no account or agreement was
  created. Text golden equality alone is not compiler or observation evidence.
- **iOS/SwiftUI:** not verified on macOS. Linux has no SwiftUI or Xcode, so `examples/ios` was not compiled. macOS
  generator CI would not substitute for this target build.
- **Kotlin beyond the example:** representative goldens were compared byte-for-byte, but not all were compiled. The
  malformed ready Toggle goldens demonstrate why this gap matters. #66 owns a repeatable generated-code Android
  compile gate.
- **Performance:** no device, simulator or emulator benchmark was run; no no-regression measurement is claimed.

## Review rule to retain

Treat generation, semantic fidelity, pending coverage and native compilation as separate checks. A byte-identical
golden can preserve an incorrect translation; a handwritten golden can itself be syntactically or semantically
wrong. Keep pending explicit, diagnose unsupported input before writing output, rebuild the CLI after every relevant
merge, and attach compile evidence to the specific generated files actually compiled.

## Interaction state and resource configuration

A token resolver alone does not demonstrate interaction semantics. The native control and the observations passed
to generated arguments must share the same interaction source; creating a separate source just for color selection
is not equivalent. Exercise real touch/focus changes and check disabled precedence during an already held native
press, not only a caller-set Boolean with no interaction lifecycle.

On Native JVM Compose, replacing `LocalContext` with a configured `ContextThemeWrapper` selects Android resources
such as `values-night`, but does not by itself change Compose's `LocalDensity`. Supply the corresponding
`LocalDensity.fontScale` as Android does for a configuration change, then measure the real text bounds and inspect
captures. `Activity.applyOverrideConfiguration` after resources are initialized throws, so a configured wrapper is
the appropriate JVM host boundary. These are explicit Native JVM configuration tests, not physical device settings,
screen-reader, HarmonyOS or performance evidence. Keep test dependencies in the fixture's `testImplementation` and
publish the labelled captures rather than inferring rendering from compilation.
