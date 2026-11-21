# Android benchmarking

## Keep Gradle generated-source wiring lazy and check with the real CLI

Use Android's `SourceDirectories.Flat.addGeneratedSourceDirectory(taskProvider, taskOutputProperty)`. This preserves
configuration avoidance and the compile dependency. A `DirectoryProperty` passed through `flatMap` retains the task
dependency. An `@OutputDirectory` must be build-owned: generate into staging, and publish only after the complete CLI
succeeds. Never delete a source directory as part of a generation task.

Do not implement a second Gradle-only stale-output checker. The CLI's `check` command owns missing, stale and extra
native-file behavior for both Kotlin and ArkTS. Supply every explicit Swift input that produces files in an output
directory, the same mapping, both resource catalogs and both reviewed output directories. If source groups need
different mappings, give each a separate reviewed output directory; comparing one group with a directory containing
another group's outputs correctly fails as unexpected. Keep a byte-checked mirror when the consumer layout differs
from another example's canonical output layout. A source group whose existing CLI invocation omits a mapping must
remain unmapped in its own Gradle source group rather than silently acquiring different generation behavior.

A Gradle `Task` already has an `inputs` property. A custom `abstract val inputs: ConfigurableFileCollection` prevents
creation of the decorated task; name it `swiftInputs` or another distinct name. A required `RegularFileProperty`
without a value fails Gradle validation before the task action. For an actionable missing-tool message, accept the
executable as an `@InputFiles` file collection and verify its single file and executable bit in the action. Include
the executable bytes as an input so switching to a different CLI invalidates generation.

A TestKit runner uses the Gradle Tooling API and does not accept `--no-daemon` as a build argument; put
`org.gradle.daemon=false` in the test project's `gradle.properties` instead. The tests create a small real Android
application and require the same SDK as the examples, rather than claiming that a plain JVM project proves Android
integration. Keep generated and reviewed Kotlin outside the default source set to avoid duplicate declarations.

An explicit publication task must not declare the reviewed source directory as an output that Gradle also observes as
another task's input. Gradle disables up-to-date when it sees that input/output overlap; a later publish can then be
skipped and leave stale source in place. Publish on every explicit invocation, and let the CLI own source publication
and rollback. Test the sequence clean → deliberately stale → failing check → explicit publish → clean check, so the
fix cannot be hidden by an earlier no-op. Keep the Swift inputs, mapping, resources and exact CLI version identical
across generation configurations; output roots, not runtime flags, select the consumer's variant.

## Match plugins to the Android Gradle Plugin version

AGP 9 includes Kotlin Android support: applying `org.jetbrains.kotlin.android` as well is a configuration error.
The Compose compiler plugin is still separate. Keep its version compatible with the Kotlin release built into AGP
and compile the project to verify, rather than assuming an older plugin block still works.

The `androidx.benchmark` Gradle plugin is for Android library microbenchmark modules, not `com.android.test`
macrobenchmark modules. A macrobenchmark test module needs the `benchmark-macro-junit4` dependency, target project
path and self-instrumenting flag, but not that Gradle plugin. Its `release` build type must be created explicitly
when the test module does not already provide it. See the error messages in the module's build file before adding
plugins indiscriminately.

Pin the compile SDK required by the actual dependency graph: `checkReleaseAarMetadata` reports if AndroidX
libraries need a newer compile SDK. That is distinct from the API level of the emulator used to execute the tests.

`createComposeRule()` needs a `ComponentActivity` in the instrumentation's target package. In a
self-instrumented test module, use `createAndroidComposeRule<MicrobenchmarkActivity>()` with that activity declared
in the test manifest. `createEmptyComposeRule()` provides no `setContent` member; it is for existing composition
content, not for setting new test UI. The activity hosts only test-owned UI and is not either measured variant.

The self-instrumenting key is `android.experimental.self-instrumenting` (hyphen), not `selfInstrumenting`; the
latter silently leaves `targetPackage` pointing at the app and causes macro permission/process failures. Use
`AndroidBenchmarkRunner` for benchmarks. Compose test rules need a host activity in the test package.

A test module cannot import another module's Kotlin classes just because it has `targetProjectPath`. Use a shared
Android library with the real generated UI, its unchanged reference and model declarations. App and test modules then
consume that library normally; sharing a Kotlin source directory across incompatible resource namespaces does not
work. A macrobenchmark runner should check the actual CLI output before compiling the tested release artifacts.

## A running emulator is not a valid benchmark by itself

Wait for `sys.boot_completed=1`, a readable `ro.build.version.sdk` (a transient 1 is not a real API level), and
responsive package, mount and SurfaceFlinger services before measuring. Check that `sm list-volumes all` has a mounted
emulated volume and that external storage is writable before AndroidX starts shell scripts. Bind every adb command to
a timeout: a booted property alone is not readiness. Do not keep restarting a known-failed software image; preserve
its blocker and provision a stable target instead. Keep raw AndroidX JSON and all Perfetto traces in a per-run output
directory immediately after each test; later tests can clean the shared additional-output directory. A complete macro
report must reject any missing scenario/variant, missing memory/frame samples, or missing trace even if another test
passed. Checksums tie the report inputs to the retained files. Instrumentation failure and absence of JSON are errors,
not empty passing reports. A headless emulator is always labelled as an emulator, never as a device.

Macrobenchmark startup needs an actual first frame within the platform deadline. Software rendering can exceed it
(`lastFrameNs=null`) even if the activity is resumable and later draws successfully. A `reportFullyDrawn()` marker
helps application readiness but does not override the platform's frame timeout. Do not delete that timeout, call
the run a pass, or present emulator timing as device evidence.

Do not assume two nearly identical top-level composables remain distinct after ART compilation. Inspect both
compiled variants and include macro frame traces; do not claim that inlining them into an identical implementation
proves no regression. Disable shrinking only as an explicit harness choice and record it with the report.

## AndroidX JSON names and samples

Use `className` to identify the benchmark class. A macrobenchmark `name` may include a variant segment before the
method name, while a microbenchmark commonly uses `Class.method`. Normalize only those explicitly supported forms
and fail closed on unknown names. Retain raw samples and calculate nearest-rank p50/p99; aggregate medians are not
raw samples. Convert `timeNs` to `timeMs` before applying the time-based gate, and do not apply a millisecond
threshold to memory or frame-overrun metrics.

Check metric names against the pinned AndroidX implementation rather than inventing a convenient canonical key.
`StartupTimingMetric` emits `timeToInitialDisplayMs` and optionally `timeToFullDisplayMs`, not `startupMs`;
`MemoryUsageMetric(Mode.Last)` includes `Last` in names such as `memoryRssAnonLastKb`. One startup or memory run
corresponds to one iteration, but a frame run is a per-frame sample across all iterations. Requiring every frame run
to have exactly `repeatIterations` entries would reject ordinary successful output. Keep per-iteration Perfetto and
memory coverage while retaining the raw frame distribution.

Bind source provenance to AndroidX's own `context.payload`. The instrumentation argument prefix is
`androidx.benchmark.output.payload.`; a `refract.sourceRevision` value under that prefix becomes a payload entry.
Check it against the probed revision, preserve the environment in the checksummed raw evidence and require a clean
unchanged source tree after measurement. A separate environment path supplied only at report time does not bind the
raw results to the same run. Duplicate JSON keys and conflicting revisions must fail closed.

When fixtures model complete macro evidence, generate all six generated/reference scenarios with ten indexed traces
each, actual metric keys, one startup/memory run per iteration and multiple frame samples. Mutate the serialized JSON
for negative cases, and use a fresh output directory for each collection attempt so earlier preserved artifacts are
not silently reused. This tests evidence handling only, never performance.

`python3 -I script.py` is preferred for scripts reading files in a worktree: it avoids current-directory module
shadowing. When loading a module with `importlib` and dataclasses, insert it into `sys.modules` before
`exec_module`, or postponed annotations may fail to resolve. Run test files directly by absolute path rather than
passing a filesystem path to `python -m unittest`.
