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
An ordinary artifact leaf is not sufficient containment: a symbolic-link `raw/` or nested parent can redirect unchanged,
correctly checksummed bytes outside the evidence root. Reject a linked root and every raw-path ancestor before hashing,
and require resolved parents to stay inside that root.
Every sample must be directly bound to its variant, scenario and iteration and to the corresponding native trace.
On iOS, also require exactly one identity-matched `xcode-metric-json` per timing measurement; a profiler trace is
supporting evidence, not a substitute for the native launch or display-interval export. Do not infer ownership from a
similar filename, duplicate a trace to fill missing iterations, or accept a median as a p99 sample.

A successful `Info.plist` parse does not establish its required dictionary schema: `plistlib` accepts legal top-level
arrays, strings and null. Require a dictionary and a nonempty string `CFBundleExecutable` before looking up the
executable, and map malformed or wrong-shaped values to the public evidence diagnostic without bypassing the bounded
read. Cover a valid dictionary, malformed XML and legal wrong-type plists through both producer and reporter entries.

JSON integers have arbitrary precision, but benchmark timing scalars are represented as finite binary floats. Convert
through a guarded boundary so an unrepresentable integer becomes `EvidenceError`, not an `OverflowError` traceback;
exercise direct and checksum-selected native measurements. Match the raw array field to the platform metric as well:
an identity-valid `frameIntervalMs` packet must not satisfy a declared HarmonyOS `frameDurationMs` measurement. Exercise
both platform-specific field names and recompute p99 from the actual duration array. Require exact integers for raw
schema, completion, iteration and PID identities: Python's `True == 1` and `4242 == 4242.0` must not make Boolean or
floating-point substitutes valid evidence. Validate artifact role and kind together: a metric JSON file cannot satisfy
the profiler requirement, whose exact trace kind is `xctrace` on iOS and `vendor-trace` on HarmonyOS.
Route original xctestrun discovery through the shared `BuildProvenanceError` boundary so the recording CLI returns its
controlled diagnostic and status 2 when the original file is missing or ambiguous.

Native trace execution needs native API and lifecycle verification, not source-wiring tests alone. `XCUIApplication`
has no supported `processIdentifier` member; obtain the app's own `ProcessInfo` PID through an identity-checked
handshake. Python's environment does not automatically reach hosted XCTest, so configure an iteration-specific
`.xctestrun` beside the original Build/Products test-run. An XCTest tap can appear hittable without delivering the
button action when a List covers the overlay; place the native Begin control in a safe-area inset and require an
identity-bound Begin acknowledgement before scenario execution. Also check the actual recorder template and output:
a simulator can reject Hitches, and `xctrace` can print `Output file saved as: <bare-package-name>` instead of an
absolute path. Match saved-output lines without consuming their terminating newline: consuming it prevents the next
immediately adjacent output line from matching and can hide a duplicate path from the exactly-one-output gate. A
newline-delimited synthetic fixture is not enough; include an end-to-end duplicate-output archive rejection. None of
these control-plane corrections permits a skipped test, incomplete scenario or failed recorder to become a passing
trace.

A synthetic XCTest fixture should make its launch boundary and ordering explicit. Use `launch()` to freeze the fresh
control epoch before starting the fixture, pass that same `Session` to capture, and wait for the current request when
it is the intended input to a negative check. The baseline helpers already preflight both supplied sessions, including
when the current request arrives first; this is deterministic clarification, not a race fix. Do not infer a stale-request
failure from a plausible ordering without reproducing it on the exact base. Never weaken stale-packet rejection to
make a test pass.

A Swift `[String: Any]` expectation containing a JSON nested dictionary cannot be checked by a comparator that only
handles scalar strings and integers. Do not add a blanket recursive `Any` comparison or numeric tolerance to repair
such a handshake: numeric JSON decoding may bridge through `NSNumber`, and a second JSON writer may choose a different
shortest decimal spelling for the same `Double`. Encode the native floating-point timestamp once as a canonical
round-trippable string, validate it and compare the typed strings exactly at each hop. Exercise the concrete native
value through the real control plane and compile the actual Swift comparator, including a mismatch rejection.

## Keep evidence domains and identity counts explicit

An inclusive identity range is not automatically its acquisition count: 2...30 contains **29 identities**. Check the
actual identity set before writing a coverage denominator, and do not silently renumber native artifacts to make an
old denominator fit. One accepted pair at iteration 30 is 1/29 of that set, not a completed 30-pair matrix.

Keep source revision, build provenance and target in every coverage statement. The accepted `eb16e22` iteration-30 pairs
in #219 are not cumulative with `95a0f37` or any other historical capture. A raw Instruments trace proves native
capture, not a complete paired scalar comparison, resource pairing, report PASS or device performance. In particular,
startup `firstDisplay` is not launch duration. Index published issue evidence separately from committed reports rather
than upgrading the production baseline implicitly.

## Equal inputs need equal native behavior

Both variants should use the same model, data, lazy-list identity, controls, accessibility and input script, but the
reference must not call the generated row or share its view implementation. Compare layout and modifier structure as
well as text. A convenient extra `frame`, asynchronous callback or dropped native token can make the two screens
non-equivalent. Compile the canonical source rather than a copied approximation, then verify actual behavior on a
named target before claiming equivalence.

Use an explicit, exclusively owned, already-booted target. Never use `booted`, create or reboot a shared simulator,
or infer ownership from an existing device name. A physical target discovered as unavailable is a blocker, not an
invitation to relabel simulator results as device evidence.
