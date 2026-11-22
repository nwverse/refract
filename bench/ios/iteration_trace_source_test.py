#!/usr/bin/env python3
"""Source wiring checks, not Swift compilation or native performance evidence."""

from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
APP = (HERE / "RefractBench/RefractBenchApp.swift").read_text()
RECORDER = (HERE / "RefractBench/BenchmarkDisplayRecorder.swift").read_text()
TESTS = (HERE / "RefractBenchUITests/RefractBenchUITests.swift").read_text()


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
        self.assertNotIn("application.processIdentifier", TESTS)
        self.assertIn('named: "completion.json"', TESTS)
        self.assertIn('name: "recorder-finished.json"', TESTS)
        self.assertIn("recorder-finished.json", TESTS)

    def test_native_process_identity_binds_the_same_pid_to_completion(self):
        identity = APP.index('publishTracePacket(named: "native-process.json"')
        ready = APP.index("while !recorderIsReady", identity)
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
                self.assertIn('in: control, expected: expectedIdentity, name: "native-completion.json")', TESTS)
        self.assertIn('expectedIdentity["state"] = "complete"', TESTS)
        self.assertIn('expectedIdentity["completion"] = completionText', TESTS)
        self.assertIn('"pid": pid', TESTS)


if __name__ == "__main__":
    unittest.main()
