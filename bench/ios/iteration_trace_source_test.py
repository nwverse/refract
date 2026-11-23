#!/usr/bin/env python3
"""Source wiring checks, not Swift compilation or native performance evidence."""

from pathlib import Path
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
        self.assertIn("let firstDisplay, firstDisplay.isFinite, firstDisplay > 0", RECORDER)
        self.assertIn('firstDisplay = ["clock": "CACurrentMediaTime", "timestamp": timestamp]', APP)
        self.assertIn("firstDisplay: firstDisplay)", APP)
        self.assertIn('Set(firstDisplay.keys) == ["clock", "timestamp"]', TESTS)
        self.assertIn('firstDisplay["clock"] as? String == "CACurrentMediaTime"', TESTS)
        self.assertIn("timestamp.isFinite, timestamp > 0", TESTS)
        self.assertIn('if scenario == "startup"', TESTS)
        self.assertNotIn("CACurrentMediaTime()", TESTS)

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


if __name__ == "__main__":
    unittest.main()
