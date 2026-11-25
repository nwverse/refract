#!/usr/bin/env python3
"""Source wiring checks, not Swift compilation or native performance evidence."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest

HERE = Path(__file__).resolve().parent
APP = (HERE / "RefractBench/RefractBenchApp.swift").read_text()
RECORDER = (HERE / "RefractBench/BenchmarkDisplayRecorder.swift").read_text()
TESTS = (HERE / "RefractBenchUITests/RefractBenchUITests.swift").read_text()
BUILD = (HERE / "build.sh").read_text()
RUNNER = (HERE / "iteration_trace_runner.py").read_text()


class TraceSourceContractTest(unittest.TestCase):
    def test_launch_protocol_and_existing_views_are_unchanged(self):
        self.assertIn("options.iterationCount = 30", TESTS)
        self.assertIn("measure(metrics: [XCTApplicationLaunchMetric()]", TESTS)
        self.assertIn("GeneratedSettingsScreen(model: model)", APP)
        self.assertIn("ReferenceSettingsScreen(model: model)", APP)
        self.assertIn('return 0..<30', APP)
        self.assertIn("static let tracedIterations = 2...30", RECORDER)
        self.assertIn("static let tracedIterations = 2...30", TESTS)
        self.assertIn("let iteration = TraceHandshake.tracedIteration(iterationValue)", TESTS)
        self.assertIn('application.launchEnvironment["REFRACT_BENCH_ITERATION"] = String(iteration)', TESTS)
        self.assertEqual(APP.count("BenchmarkDisplayRecorder.tracedIterations.contains(iteration)"), 3)
        self.assertEqual(RECORDER.count("Self.tracedIterations.contains(iteration)"), 3)
        self.assertIn("iteration == completedIterations, (0..<30).contains(iteration)", RECORDER)
        self.assertIn("TRACED_ITERATIONS = range(2, 31)", RUNNER)
        self.assertEqual(RUNNER.count("iteration not in TRACED_ITERATIONS"), 2)
        readme = (HERE / "README.md").read_text()
        self.assertIn("2...30 inclusive", readme)
        self.assertIn("--iteration <2-through-30>", readme)

    def test_selected_iteration_uses_the_same_native_input_step(self):
        self.assertIn("await scrollStep(iteration: iteration)", APP)
        self.assertIn("for iteration in iterationRange()", APP)
        self.assertIn("for _ in 0..<8", APP)
        self.assertIn('model.setEnabled(0, value: !model.rows[0].enabled)', APP)
        self.assertIn("NotificationCenter.default.post(name: .refractBenchmarkScroll", APP)
        self.assertIn('guard active, scenario == self.scenario else { return }', RECORDER)
        self.assertIn('if selectedIteration != nil || completedIterations == 30', RECORDER)

    def test_selected_iteration_consumes_begin_before_native_input(self):
        ready = TESTS.index('readyText.waitForExistence')
        tap = TESTS.index("begin.tap()", ready)
        expected = TESTS.index('expectedBegin["state"] = "begin"', tap)
        acknowledgement = TESTS.index('name: "begin.json"', expected)
        scenario = APP.index("Task { await runTracedIteration")
        self.assertLess(ready, tap)
        self.assertLess(tap, expected)
        self.assertLess(expected, acknowledgement)
        self.assertIn('publishTracePacket(named: "begin.json"', APP[:scenario])
        self.assertLess(APP.index(".safeAreaInset(edge: .bottom)"), APP.index("Button(\"BeginIteration\", action: beginTrace)"))
        self.assertNotIn("native-button-action", APP)

    def test_recorder_ready_precedes_button_and_native_completion(self):
        start = TESTS.index('try TraceHandshake.write(packet, named: "request.json"')
        ready = TESTS.index('The distinct Instruments recorder did not become ready', start)
        tap = TESTS.index("begin.tap()", ready)
        complete = TESTS.index("completion.waitForExistence", tap)
        self.assertLess(start, ready)
        self.assertLess(ready, tap)
        self.assertLess(tap, complete)
        self.assertNotIn("application.processIdentifier", TESTS)
        self.assertIn('named: "completion.json"', TESTS)
        self.assertIn('name: "recorder-finished.json"', TESTS)
        self.assertIn("recorder-finished.json", TESTS)

    def test_native_process_identity_binds_the_same_pid_to_completion(self):
        identity = APP.index('appendingPathComponent("native-process.json")')
        ready = APP.index("while !recorderReady", identity)
        scenario = APP.index("switch (variant, scenario)", ready)
        completion = APP.index('publishTracePacket(named: "native-completion.json"', scenario)
        self.assertLess(identity, ready)
        self.assertLess(ready, scenario)
        self.assertLess(scenario, completion)
        for field in ('"revision": revision', '"variant": variant', '"scenario": scenario',
                      '"iteration": iteration', '"pid": Int(ProcessInfo.processInfo.processIdentifier)',
                      '"process": "running"'):
            self.assertIn(field, APP)
        for name in ("native-process.json", "native-completion.json"):
            if name == "native-process.json":
                self.assertIn('TraceHandshake.ready(in: control, expected: expectedIdentity,\n'
                              '                                     name: "native-process.json")', TESTS)
            else:
                native_completion = TESTS.index('name: "native-completion.json")')
        completion_wait = TESTS.index("nativeCompletion", native_completion)
        write_completion = TESTS.index('try TraceHandshake.write(completionPacket, named: "completion.json"', completion_wait)
        self.assertLess(native_completion, completion_wait)
        self.assertLess(completion_wait, write_completion)
        self.assertIn('XCTWaiter.wait(for: [nativeCompletion], timeout: 30)', TESTS)
        self.assertIn('expectedIdentity["state"] = "complete"', TESTS)
        self.assertIn('expectedIdentity["completion"] = completionText', TESTS)
        self.assertIn('expectedIdentity["pid"] = pid', TESTS)
        self.assertIn('completionPID == pid', TESTS)
        self.assertIn('expectedFinished["state"] = "recorder-finished"', TESTS)
        self.assertIn('TraceHandshake.ready(in: control, expected: expectedFinished,', TESTS)
        self.assertIn('"pid": pid', TESTS)


    def test_duplicate_native_packets_fail_before_completion_is_forwarded(self):
        check = TESTS.index('if name == "native-process.json" || name == "native-completion.json" || name == "begin.json"')
        unique = TESTS.index('entries.filter({ $0.hasPrefix(stem) && $0.hasSuffix(".json") }).sorted() == [name]', check)
        failure = TESTS.index('XCTFail("Missing or ambiguous', unique)
        self.assertLess(check, unique)
        self.assertLess(unique, failure)
        for name in ("native-process.json", "native-completion.json", "begin.json"):
            self.assertIn(f'name == "{name}"', TESTS[check:unique])
        self.assertIn("name: \"native-completion.json\") != nil", TESTS)
        self.assertLess(TESTS.index("completionPID == pid"),
                        TESTS.index('try TraceHandshake.write(completionPacket, named: "completion.json"'))

    def test_startup_uses_recorded_first_display_in_the_same_native_completion(self):
        ready = APP.index('case ("generated", "startup"), ("reference", "startup"):')
        completion = APP.index("completeStartup(iteration: iteration)", ready)
        publish = APP.index('publishTracePacket(named: "native-completion.json"', completion)
        self.assertLess(ready, completion)
        self.assertLess(completion, publish)
        self.assertIn('guard active, scenario == "startup", selectedIteration == iteration', RECORDER)
        self.assertIn("Self.tracedIterations.contains(iteration), let firstDisplay", RECORDER)
        self.assertIn("let firstDisplay, firstDisplay.isFinite, firstDisplay > 0", RECORDER)
        self.assertIn('firstDisplay = ["clock": "CACurrentMediaTime", "timestamp": String(timestamp)]', APP)
        self.assertIn("firstDisplay: firstDisplay, finalSamples: finalSamples)", APP)
        self.assertIn('let firstDisplay = scenario == "startup" ? try TraceHandshake.firstDisplay(in: completionPacket) : nil',
                      TESTS)
        self.assertIn('if let firstDisplay {', TESTS)
        self.assertIn('expectedFinished["firstDisplay"] = firstDisplay', TESTS)
        self.assertNotIn("CACurrentMediaTime()", TESTS)

    def test_startup_duration_is_exported_only_after_the_exact_test_succeeds(self):
        helper = TESTS[TESTS.index("    private func tracedStartupMetric"):
                       TESTS.index("    private func launchMetric")]
        self.assertIn("options.iterationCount = 1", helper)
        self.assertEqual(helper.count('try runTracedIteration("startup", variant: variant)'), 2)
        self.assertEqual(helper[helper.index("measure(metrics:"):].count(
            'try runTracedIteration("startup", variant: variant)'), 1)
        self.assertIn("A throwing measure block cannot preserve XCTSkip", helper)
        self.assertIn("var iterationError: Error?", helper)
        self.assertIn("throw iterationError", helper)
        self.assertEqual(TESTS.count("options.iterationCount = 30"), 1)
        self.assertEqual(TESTS.count("options.iterationCount = 1"), 1)
        completed = RUNNER.index("if status != 0:")
        export = RUNNER.index("result[\"native_launch_metric\"] = export_launch_metric(", completed)
        self.assertLess(completed, export)
        self.assertLess(export, RUNNER.index("print(json.dumps(result", export))
        self.assertIn('if args.scenario == "startup":', RUNNER[completed:export])
        exporter = (HERE / "launch_metric.py").read_text()
        self.assertIn('"--test-id", identifier', exporter)
        self.assertIn('com.apple.dt.XCTMetric_ApplicationLaunch-AppLaunch.duration', exporter)
        self.assertIn("data = bounded_export_output(command, run_command)", exporter)
        self.assertIn("write_once(destination / name, data)", exporter)
        self.assertNotIn("capture_output=True", exporter)
        self.assertNotIn("firstDisplay", exporter[exporter.index("def selected_launch_measurement"):
                                                  exporter.index("def export_launch_metric")])

    def test_first_display_is_compared_as_one_exact_string_not_an_unsupported_dictionary(self):
        forward = TESTS.index('try TraceHandshake.write(completionPacket')
        expected = TESTS.index('var expectedFinished = completionPacket', forward)
        startup = TESTS.index('static func firstDisplay(')
        self.assertIn('guard let firstDisplay = completionPacket["firstDisplay"] as? [String: String]',
                      TESTS[startup:forward])
        self.assertIn('expectedFinished["firstDisplay"] = firstDisplay', TESTS[expected:])
        equality = TESTS.index("private static func isEqual")
        comparator = TESTS[equality:TESTS.index("\n    }\n}", equality)]
        self.assertIn('case let value as [String: String]: return lhs as? [String: String] == value', comparator)
        self.assertNotIn("[String: Any]", comparator)
        self.assertIn('type(text) is not str', RUNNER)
        self.assertIn("repr(timestamp) != text", RUNNER)

    def test_final_samples_are_published_after_native_input_and_before_completion(self):
        completion_call = APP.index('BenchmarkDisplayRecorder.shared.finalSamples(iteration: iteration)')
        publish = APP.index('publishTracePacket(named: "native-completion.json"', completion_call)
        self.assertLess(APP.index("await runUpdates(variant: variant, model: model)"), completion_call)
        self.assertLess(APP.index("await runScroll(variant: variant, model: model)"), completion_call)
        self.assertLess(completion_call, publish)
        self.assertIn("firstDisplay: firstDisplay, finalSamples: finalSamples)", APP)
        self.assertIn('packet["finalSamples"] = finalSamples', APP)
        self.assertIn("func finalSamples(iteration: Int) -> [String: Any]?", RECORDER)
        for condition in (
            "selectedIteration == iteration", "Self.tracedIterations.contains(iteration)", "completedIterations == 1",
            "frames.allSatisfy({ $0.isFinite && $0 > 0 })", "iterations.count == frames.count",
            "iterations.allSatisfy({ $0 == iteration })", "completion?.count == 1",
        ):
            self.assertIn(condition, RECORDER)
        self.assertIn("UserDefaults.standard.set(data, forKey: framesKey)", RECORDER)
        self.assertNotIn("synchronize()", APP + RECORDER + TESTS)

    def test_ui_test_validates_final_samples_before_forwarding_completion(self):
        guard = TESTS.index("guard let samples = completionPacket[\"finalSamples\"]")
        for field in ('samples["sourceRevision"] as? String == revision',
                      'exactInteger(samples["pid"], equals: pid)',
                      'exactInteger(samples["completedIterations"], equals: 1)',
                      'exactInteger(samples["recordedIteration"], equals: iteration)',
                      'exactFinitePositiveDouble($0) != nil',
                      'exactInteger($0, equals: iteration)'):
            self.assertIn(field, TESTS[guard:TESTS.index("private static func isEqual", guard)])
        validation = TESTS.index("try TraceHandshake.finalSamples(")
        forwarded = TESTS.index('try TraceHandshake.write(completionPacket, named: "completion.json"', validation)
        self.assertLess(validation, forwarded)

    def test_runner_archives_only_validated_final_samples_not_preferences(self):
        validation = RUNNER.index("checked_final_samples(native_completion, self, pid)")
        forwarded = RUNNER.index("checked_final_samples(completion, self, pid)", validation)
        archive = RUNNER.index("archive_trace(self.trace, self.archive)", forwarded)
        self.assertLess(validation, forwarded)
        self.assertLess(forwarded, archive)
        self.assertIn("final_samples != native_final_samples", RUNNER)
        self.assertIn("first_display != native_first_display", RUNNER)
        self.assertIn('atomic_json(self.raw / "native-samples.json", final_samples)', RUNNER)
        self.assertNotIn("refract.bench.frames", RUNNER)
        self.assertNotIn("UserDefaults", RUNNER)

    def test_build_and_trace_provenance_precedes_unchanged_capture_contract(self):
        build = BUILD.index("build-for-testing")
        source_check = BUILD.index('git -C "$root" rev-parse HEAD', build)
        record = BUILD.index("record_build_provenance.py", build)
        self.assertLess(build, source_check)
        self.assertLess(source_check, record)
        validate = RUNNER.index("validate_build_provenance(args.derived_data")
        prepare = RUNNER.index("test_run = prepare_test_run(", validate)
        self.assertLess(validate, prepare)
        self.assertLess(prepare, RUNNER.index("test_command(test_run", prepare))
        self.assertIn('parser.add_argument("--readiness-timeout", type=float, default=60)', RUNNER)
        self.assertIn('parser.add_argument("--completion-timeout", type=float, default=180)', RUNNER)
        self.assertIn('"-only-testing:{test}"', RUNNER)


class SwiftTracedIterationDomainTest(unittest.TestCase):
    def test_native_ready_and_recorder_guards_admit_29_30_and_reject_31(self):
        swift = os.environ.get("REFRACT_SWIFTC") or shutil.which("swiftc")
        if swift is None:
            self.fail("The focused Swift source regression requires a Swift toolchain")
        recorder_start = RECORDER.index("    // #219 has exactly thirty traced identities:")
        recorder_range = RECORDER[recorder_start:RECORDER.index("\n\n", recorder_start)]
        test_start = TESTS.index("    static let tracedIterations =")
        test_domain = TESTS[test_start:TESTS.index("    static func write(", test_start)]
        for marker in (
            "guard let iteration = selectedIteration(), BenchmarkDisplayRecorder.tracedIterations.contains(iteration)",
            "Self.tracedIterations.contains(iteration), let firstDisplay",
            "guard iteration == selectedIteration, Self.tracedIterations.contains(iteration)",
        ):
            self.assertIn(marker, APP + RECORDER)
        script = textwrap.dedent("""
            import Foundation

            enum BenchmarkDisplayRecorder {
            @RECORDER_RANGE@
            }

            enum TraceHandshake {
            @TEST_DOMAIN@
            }

            precondition(Array(BenchmarkDisplayRecorder.tracedIterations) == Array(2...30),
                         "domain must contain exactly 2...30")
            precondition(BenchmarkDisplayRecorder.tracedIterations.lowerBound == 2)
            precondition(BenchmarkDisplayRecorder.tracedIterations.upperBound == 30)
            precondition(TraceHandshake.tracedIterations.lowerBound == 2)
            precondition(TraceHandshake.tracedIterations.upperBound == 30)
            for iteration in [29, 30] {
                precondition(TraceHandshake.tracedIteration(String(iteration)) == iteration,
                             "accepted identity \\(iteration) must survive parsing")
                precondition(BenchmarkDisplayRecorder.tracedIterations.contains(iteration),
                             "recorder must accept \\(iteration)")
            }
            precondition(TraceHandshake.tracedIteration("030") == 30, "integer spelling 030 is the same identity")
            for value in ["31", "1", "0", "30.0", " 30", "", "not-an-integer"] {
                precondition(TraceHandshake.tracedIteration(value) == nil,
                             "unexpected parsed value for \\(value.debugDescription): \\(String(describing: TraceHandshake.tracedIteration(value)))")
            }
            for iteration in [31, 1, 0] {
                precondition(!BenchmarkDisplayRecorder.tracedIterations.contains(iteration),
                             "recorder accepted out-of-domain \\(iteration)")
            }
            print("exact Swift traced iteration domain passed")
            """).lstrip().replace("@RECORDER_RANGE@", recorder_range).replace("@TEST_DOMAIN@", test_domain)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "main.swift"
            path.write_text(script)
            result = subprocess.run([swift, str(path), "-o", str(Path(temporary) / "iteration-check")],
                                    capture_output=True, text=True, timeout=60, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(Path(temporary) / "iteration-check")],
                                    capture_output=True, text=True, timeout=30, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("exact Swift traced iteration domain passed", result.stdout)


class SwiftFinalSamplesContractTest(unittest.TestCase):
    def test_extracted_native_ui_validation_round_trips_and_rejects_corruption(self):
        swift = os.environ.get("REFRACT_SWIFTC") or shutil.which("swiftc")
        if swift is None:
            self.fail("The focused Swift source regression requires a Swift toolchain")
        start = TESTS.index("    static func ready(")
        ready = TESTS[start:TESTS.index("    static func firstDisplay", start)]
        start = TESTS.index("    static func finalSamples(")
        end = TESTS.index("\n}\n\n@MainActor\nfinal class", start)
        validation = TESTS[start:end]
        script = '''import Foundation

enum ContractFailure: Error { case mismatch }
enum TraceHandshake {
@READY@
@VALIDATION@
}
func XCTFail(_ message: String) {}
func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw ContractFailure.mismatch }
    return value
}
func check(_ samples: [String: Any], valid: Bool) {
    guard let data = try? JSONSerialization.data(withJSONObject: ["finalSamples": samples]) else {
        precondition(!valid, "non-JSON invalid sample must be rejected")
        return
    }
    checkPacket(data, valid: valid)
}
func checkPacket(_ data: Data, valid: Bool, label: String = "typed") {
    do {
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        _ = try TraceHandshake.finalSamples(in: decoded, revision: "revision",
                                           variant: "generated", scenario: "scroll", iteration: 2, pid: 42)
        precondition(valid, "accepted invalid final native samples: \\(label)")
    } catch {
        precondition(!valid, "rejected valid final native samples \\(label): \\(error)")
    }
}
let original: [String: Any] = [
    "schema": 1, "session": 1, "sourceRevision": "revision", "variant": "generated",
    "scenario": "scroll", "iteration": 2, "pid": 42, "completedIterations": 1,
    "recordedIteration": 2, "frameIntervalMs": [16.666666666666668, 16.5],
    "iterationByFrame": [2, 2],
]
let encoded = try JSONSerialization.data(withJSONObject: ["finalSamples": original], options: [.sortedKeys])
let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
let samples = try XCTUnwrap(decoded["finalSamples"] as? [String: Any])
for iteration in [29, 30] {
    for scenario in ["scroll", "stateUpdate"] {
        var boundary = samples
        boundary["iteration"] = iteration
        boundary["recordedIteration"] = iteration
        boundary["iterationByFrame"] = [iteration, iteration]
        boundary["scenario"] = scenario
        _ = try TraceHandshake.finalSamples(in: ["finalSamples": boundary], revision: "revision",
                                           variant: "generated", scenario: scenario,
                                           iteration: iteration, pid: 42)
    }
}
check(samples, valid: true)
for key in original.keys {
    var partial = samples
    partial.removeValue(forKey: key)
    check(partial, valid: false)
}
for (key, value) in [("sourceRevision", "stale"), ("session", 2), ("iteration", 1),
                     ("pid", 43), ("completedIterations", 0), ("recordedIteration", 1)] as [(String, Any)] {
    var changed = samples
    changed[key] = value
    check(changed, valid: false)
}
for invalid in [
    ["session": true], ["pid": true], ["completedIterations": true],
    ["frameIntervalMs": [9007199254740993]],
] as [[String: Any]] {
    var changed = samples
    for (key, value) in invalid {
        changed[key] = value
    }
    check(changed, valid: false)
}
for intervals in [[], [Double.nan], [Double.infinity], [0.0], [-1.0], [true],
                  [16.5, 16.5, 16.5]] {
    var changed = samples
    changed["frameIntervalMs"] = intervals
    check(changed, valid: false)
}
for tags in [[2, 1], [true, true], [9007199254740993, 9007199254740993]] {
    var changed = samples
    changed["iterationByFrame"] = tags
    check(changed, valid: false)
}
var tags = samples
tags["iterationByFrame"] = [2, 1]
check(tags, valid: false)
var ordinaryDouble = samples
ordinaryDouble["frameIntervalMs"] = [16.5] as [Double]
ordinaryDouble["iterationByFrame"] = [2]
check(ordinaryDouble, valid: true)
// Keep raw JSON spellings: serializing a typed huge integer into a test packet
// first would erase the representation boundary that this regression checks.
let rawPacket = #"{"finalSamples":{"schema":1,"session":1,"sourceRevision":"revision","variant":"generated","scenario":"scroll","iteration":2,"pid":42,"completedIterations":1,"recordedIteration":2,"frameIntervalMs":[INTERVAL],"iterationByFrame":[2]}}"#
for (interval, valid) in [
    ("9007199254740992", true), ("9007199254740992.0", true), ("1e19", false),
    ("9007199254740993", false), ("9007199254740994", false),
    ("18446744073709551615", false), ("18446744073709551616", false),
    ("18446744073709551617", false), ("18446744073709551618", false),
    ("18446744073709551619", false), ("18446744073709551620", false),
    ("18446744073709551616.0", false), ("18446744073709551617.0", false),
    ("1.8446744073709552e19", false),
] {
    let json = rawPacket.replacingOccurrences(of: "INTERVAL", with: interval)
    precondition(json != rawPacket, "raw JSON case must replace the interval spelling")
    checkPacket(Data(json.utf8), valid: valid, label: interval)
}
let control = FileManager.default.temporaryDirectory
    .appendingPathComponent("refract-final-samples-\\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: control) }
try JSONSerialization.data(withJSONObject: ["schema": true], options: [.sortedKeys])
    .write(to: control.appendingPathComponent("boolean-ready.json"))
precondition(TraceHandshake.ready(in: control, expected: ["schema": 1], name: "boolean-ready.json") == nil,
             "Boolean schema must not bridge to integer identity")
func writeFinished(_ packet: [String: Any]) throws {
    try JSONSerialization.data(withJSONObject: packet, options: [.sortedKeys])
        .write(to: control.appendingPathComponent("recorder-finished.json"))
}
try writeFinished(decoded)
precondition(TraceHandshake.ready(in: control, expected: decoded,
                                 name: "recorder-finished.json") != nil,
             "valid finalSamples must survive the complete forwarding comparison")
var mismatched = decoded
mismatched["finalSamples"] = tags
try writeFinished(mismatched)
precondition(TraceHandshake.ready(in: control, expected: mismatched,
                                 name: "recorder-finished.json") != nil,
             "equal corrupted finalSamples must survive the forwarding comparison")
try writeFinished(decoded)
precondition(TraceHandshake.ready(in: control, expected: mismatched,
                                 name: "recorder-finished.json") == nil,
             "forwarding must reject mismatched finalSamples")
precondition(TraceHandshake.ready(in: control, expected: ["state": "recorder-finished"],
                                 name: "recorder-finished.json") == nil)
print("exact Swift final sample validation passed")
'''.replace("@READY@", ready).replace("@VALIDATION@", validation)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "main.swift"
            path.write_text(script)
            result = subprocess.run([swift, str(path), "-o", str(Path(temporary) / "samples-check")],
                                    capture_output=True, text=True, timeout=60, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(Path(temporary) / "samples-check")],
                                    capture_output=True, text=True, timeout=30, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("exact Swift final sample validation passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
