# Paired native performance evidence

## Compile-only scenarios and blockers are not measurements

A shared SwiftUI file and independently written native reference can be compiled without creating or selecting a
simulator. Use explicit `generic/platform=iOS Simulator` or `generic/platform=iOS` `build-for-testing` commands for
that evidence, and report them as compiler results only. A generic physical-SDK destination does not prove that a
physical device is attached, authorized, signed or measured.

A benchmark issue whose acceptance permits an explicit toolchain/target blocker should record the exact missing
prerequisite, preserve the source-prepared reference and stop short of any timing claim. Do not turn source inspection,
an SDK-independent generation check or a synthetic report test into a performance result. Keep the production gate
open even when the tracking issue may close through its blocker branch.

## Native metrics and traces have different meanings

`XCTApplicationLaunchMetric` is not a shell stopwatch. `CADisplayLink`'s `targetTimestamp - timestamp` is a display
interval, not a CPU frame duration. A vendor frame profiler's frame duration is a different metric again. Keep the
metric definition in the report and never compare absolute numbers across operating systems, targets or toolchains.

A `.xcresult` bundle, Instruments `.trace` recording, vendor trace and UI test timing are separate raw artifacts.
Preserve them with exact source/toolchain/target metadata, acquisition/export commands and checksums. ZIP result and
Instruments packages when ordinary files are needed for public review; a directory named `.trace` is not a trace file.
`bench/ios/archive_trace.py` archives only an already completed package, never overwrites output and does not establish
that capture finished or that a package belongs to a measurement.
Every sample must be directly bound to its variant, scenario and iteration and to the corresponding native trace.
On iOS, also require exactly one identity-matched `xcode-metric-json` per timing measurement; a profiler trace is
supporting evidence, not a substitute for the native launch or display-interval export. Do not infer ownership from a
similar filename, duplicate a trace to fill missing iterations, or accept a median as a p99 sample.

Native trace execution needs native API and lifecycle verification, not source-wiring tests alone. `XCUIApplication`
has no supported `processIdentifier` member; obtain the app's own `ProcessInfo` PID through an identity-checked
handshake. Python's environment does not automatically reach hosted XCTest, so configure an iteration-specific
`.xctestrun` beside the original Build/Products test-run. An XCTest tap can appear hittable without delivering the
button action when a List covers the overlay; place the native Begin control in a safe-area inset and require an
identity-bound Begin acknowledgement before scenario execution. Also check the actual recorder template and output:
a simulator can reject Hitches, and `xctrace` can print `Output file saved as: <bare-package-name>` instead of an
absolute path. None of these control-plane corrections permits a skipped test, incomplete scenario or failed
recorder to become a passing trace.

## Equal inputs need equal native behavior

Both variants should use the same model, data, lazy-list identity, controls, accessibility and input script, but the
reference must not call the generated row or share its view implementation. Compare layout and modifier structure as
well as text. A convenient extra `frame`, asynchronous callback or dropped native token can make the two screens
non-equivalent. Compile the canonical source rather than a copied approximation, then verify actual behavior on a
named target before claiming equivalence.

Use an explicit, exclusively owned, already-booted target. Never use `booted`, create or reboot a shared simulator,
or infer ownership from an existing device name. A physical target discovered as unavailable is a blocker, not an
invitation to relabel simulator results as device evidence.
