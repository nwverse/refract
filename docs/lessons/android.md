# Android benchmarking

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

## A running emulator is not a valid benchmark by itself

Without hardware acceleration, a first boot can take a long time optimizing system packages. Wait for
`sys.boot_completed=1` and for initial dex optimization/system load to settle before measuring. Keep raw AndroidX
JSON; instrumentation failure and absence of JSON are errors, not empty passing reports. A headless emulator is
always labelled as an emulator, never as a physical-device result.

Do not assume two nearly identical top-level composables remain distinct after ART compilation. Inspect both
compiled variants and include macro frame traces; do not claim that inlining them into an identical implementation
proves no regression. Disable shrinking only as an explicit harness choice and record it with the report.

## AndroidX JSON names and samples

Use `className` to identify the benchmark class. A macrobenchmark `name` may include a variant segment before the
method name, while a microbenchmark commonly uses `Class.method`. Normalize only those explicitly supported forms
and fail closed on unknown names. Retain raw samples and calculate nearest-rank p50/p99; aggregate medians are not
raw samples. Convert `timeNs` to `timeMs` before applying the time-based gate, and do not apply a millisecond
threshold to memory or frame-overrun metrics.

`python3 -I script.py` is preferred for scripts reading files in a worktree: it avoids current-directory module
shadowing. When loading a module with `importlib` and dataclasses, insert it into `sys.modules` before
`exec_module`, or postponed annotations may fail to resolve. Run test files directly by absolute path rather than
passing a filesystem path to `python -m unittest`.
