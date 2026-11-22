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
        ready = APP.index("while !recorderIsReady")
        begin = APP.index("while !beginSelectedIteration", ready)
        scenario = APP.index("switch (variant, scenario)", begin)
        self.assertLess(ready, begin)
        self.assertLess(begin, scenario)

    def test_recorder_ready_precedes_button_and_native_completion(self):
        start = TESTS.index('try TraceHandshake.write(packet, named: "request.json"')
        ready = TESTS.index('The distinct Instruments recorder did not become ready', start)
        tap = TESTS.index("begin.tap()", ready)
        complete = TESTS.index("completion.waitForExistence", tap)
        self.assertLess(start, ready)
        self.assertLess(ready, tap)
        self.assertLess(tap, complete)
        self.assertIn("Int(application.processIdentifier)", TESTS)
        self.assertIn('named: "completion.json"', TESTS)
        self.assertIn('name: "recorder-finished.json"', TESTS)
        self.assertIn("recorder-finished.json", TESTS)


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
