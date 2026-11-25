#!/usr/bin/env python3
"""Synthetic XCTest export tests; no target, Xcode or Instruments is invoked."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "common"))

from launch_metric import (LAUNCH_METRIC, LaunchMetricError, export_launch_metric,
                           selected_launch_measurement, traced_test_identifier)
from paired_report import selected_duration

REVISION = "a" * 40
TARGET = "synthetic-target"
NATIVE_PID = 4242
IDENTIFIER = "RefractBenchUITests/testGeneratedStartupTrace()"
IDENTIFIER_URL = ("test://com.apple.xcode/RefractBench/RefractBenchUITests/"
                  "RefractBenchUITests/testGeneratedStartupTrace")


def synthetic_metrics(**changes):
    metric = {"identifier": LAUNCH_METRIC, "displayName": "Application Launch",
              "unitOfMeasurement": "s", "measurements": [1.25]}
    metric.update(changes.pop("metric_changes", {}))
    payload = [{"testIdentifier": IDENTIFIER, "testIdentifierURL": IDENTIFIER_URL,
                "testRuns": [{"device": {"deviceId": TARGET, "deviceName": "Synthetic"},
                              "testPlanConfiguration": {"configurationId": "1",
                                                        "configurationName": "Test Scheme Action"},
                              "metrics": [metric]}]}]
    payload[0].update(changes)
    return payload


def synthetic_tests(**changes):
    case = {"name": IDENTIFIER, "nodeIdentifier": IDENTIFIER, "nodeIdentifierURL": IDENTIFIER_URL,
            "nodeType": "Test Case", "result": "Passed", "durationInSeconds": 26.5}
    case.update(changes.pop("case_changes", {}))
    payload = {"testPlanConfigurations": [{"configurationId": "1",
                                           "configurationName": "Test Scheme Action"}],
               "testNodes": [{"nodeType": "Test Plan", "children": [
                   {"nodeType": "UI test bundle", "children": [
                       {"nodeType": "Test Suite", "children": [case]}]}]}]}
    payload.update(changes)
    return payload


class LaunchMetricSelectionTest(unittest.TestCase):
    def select(self, metrics=None, tests=None):
        return selected_launch_measurement(
            synthetic_metrics() if metrics is None else metrics,
            synthetic_tests() if tests is None else tests,
            variant="generated", revision=REVISION, iteration=30, target_udid=TARGET,
            trace={"path": HERE / "iteration_trace_runner.py"},
            configuration={"path": HERE / "iteration_trace_runner.py"},
            native_pid=NATIVE_PID, native_packets={})

    def test_one_exact_selector_native_second_becomes_one_millisecond_duration(self):
        selected, duration = self.select()
        self.assertEqual(duration, 1250.0)
        measurement = selected["measurements"][0]
        self.assertEqual(measurement["nativeValue"], {"unitOfMeasurement": "s", "measurements": [1.25]})
        self.assertEqual(measurement["nativeTestIdentifier"], IDENTIFIER)
        self.assertEqual(measurement["iteration"], 30)
        self.assertEqual(measurement["pid"], NATIVE_PID)
        self.assertNotIn("firstDisplay", measurement)
        self.assertNotIn("timestamp", measurement)
        self.assertNotIn("durationInSeconds", measurement)
        self.assertEqual(selected_duration(selected, ("generated", "startup", 30), REVISION,
                                           selected["metric_selector"]), duration)
        for variant in ("generated", "reference"):
            with self.subTest(variant=variant):
                self.assertEqual(traced_test_identifier(variant),
                                 f"RefractBenchUITests/test{variant.capitalize()}StartupTrace()")
        with self.assertRaises(LaunchMetricError):
            traced_test_identifier("another")

    def test_empty_actual_shape_and_ambiguous_or_unrelated_metrics_fail_closed(self):
        cases = [
            ("empty-actual-export", []),
            ("empty-test-runs", [{"testIdentifier": IDENTIFIER, "testRuns": []}]),
            ("no-metrics", synthetic_metrics(metric_changes={"measurements": []})),
            ("two-automatic-iterations-cannot-be-renumbered",
             synthetic_metrics(metric_changes={"measurements": [1.25, 1.5]})),
            ("duplicate-tests", synthetic_metrics() + synthetic_metrics()),
            ("unrelated-selector", synthetic_metrics(testIdentifier="RefractBenchUITests/testGeneratedColdStart()")),
            ("unrelated-metric", synthetic_metrics(metric_changes={"identifier": "other.metric"})),
            ("wrong-unit", synthetic_metrics(metric_changes={"unitOfMeasurement": "ms"})),
            ("missing-unit", synthetic_metrics(metric_changes={"unitOfMeasurement": None})),
            ("different-target", synthetic_metrics(testRuns=[{
                "device": {"deviceId": "different-target"},
                "testPlanConfiguration": {"configurationId": "1", "configurationName": "Test Scheme Action"},
                "metrics": [{"identifier": LAUNCH_METRIC, "unitOfMeasurement": "s", "measurements": [1.25]}],
            }])),
        ]
        for name, metrics in cases:
            with self.subTest(name=name), self.assertRaises(LaunchMetricError):
                self.select(metrics=metrics)

    def test_nonfinite_nonpositive_and_wrong_typed_native_values_fail_closed(self):
        for value in (0, -1, True, "1.25", None, 10**400):
            with self.subTest(value=value), self.assertRaises(LaunchMetricError):
                self.select(metrics=synthetic_metrics(metric_changes={"measurements": [value]}))
        for value in ("NaN", "Infinity"):
            with self.subTest(value=value), self.assertRaises(LaunchMetricError):
                self.select(metrics=json.loads('[' + value + ']'))

    def test_wrong_failed_or_duplicate_test_result_cannot_bind_a_metric(self):
        cases = [
            synthetic_tests(case_changes={"result": "Failed"}),
            synthetic_tests(case_changes={"name": "testGeneratedColdStart()"}),
            synthetic_tests(case_changes={"nodeIdentifier": "RefractBenchUITests/testGeneratedColdStart()"}),
            synthetic_tests(case_changes={"nodeIdentifierURL": "test://another-result"}),
            synthetic_tests(case_changes={"durationInSeconds": None}),
            synthetic_tests(testPlanConfigurations=[]),
        ]
        for tests in cases:
            with self.subTest(tests=tests), self.assertRaises(LaunchMetricError):
                self.select(tests=tests)
        with self.assertRaises(LaunchMetricError):
            self.select(tests={})
        metrics = synthetic_metrics()
        metrics[0]["testRuns"].append(copy.deepcopy(metrics[0]["testRuns"][0]))
        with self.assertRaises(LaunchMetricError):
            self.select(metrics=metrics)
        metrics = synthetic_metrics()
        metrics[0]["testRuns"][0]["metrics"] = []
        with self.assertRaises(LaunchMetricError):
            self.select(metrics=metrics)


class LaunchMetricExportTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.run = self.root / "generated-startup-30"
        (self.run / "raw").mkdir(parents=True)
        (self.run / "control").mkdir()
        (self.run / "results.xcresult").mkdir()
        (self.run / "results.xcresult/Info.plist").write_bytes(b"synthetic xcresult")
        (self.run / "iteration-trace-config.xctestrun").write_bytes(plistlib.dumps({
            "RefractBenchUITests": {"TestingEnvironmentVariables": {
                "REFRACT_BENCH_REVISION": REVISION,
                "REFRACT_BENCH_TRACE_CONTROL": str(self.run / "control"),
                "REFRACT_BENCH_TRACE_ITERATION": "30",
            }},
        }))
        (self.run / "refract-build-provenance.json").write_bytes(b"synthetic build provenance")
        self.receipt = {
            "status": "complete", "source_revision": REVISION, "variant": "generated",
            "scenario": "startup", "iteration": 30, "session": 1, "pid": NATIVE_PID,
            "target_udid": TARGET, "target_label": "SIMULATOR", "device_result": False,
            "native_iteration_completion": "generated startup complete 1",
            "native_first_display": {"clock": "CACurrentMediaTime", "timestamp": "12345.25"},
        }
        self.packet_paths = {
            "native_process": self.run / "control/native-process.json",
            "request": self.run / "raw/request.json",
            "native_completion": self.run / "control/native-completion.json",
            "completion": self.run / "raw/completion.json",
        }
        self.packets = {}
        for role, path in self.packet_paths.items():
            packet = {
                "schema": 1, "session": 1, "revision": REVISION, "variant": "generated",
                "scenario": "startup", "iteration": 30, "pid": NATIVE_PID, "process": "running",
                "state": "complete" if role.endswith("completion") else "ready",
            }
            if role.endswith("completion"):
                packet["completion"] = "generated startup complete 1"
            self.packets[role] = packet
            path.write_text(json.dumps(packet))
        (self.run / "raw/iteration-trace.json").write_text(json.dumps(self.receipt))
        configuration = {
            "schema": 1, "archive": "iteration-trace-config.xctestrun",
            "source_revision": REVISION, "iteration": 30,
            "control_directory": str(self.run / "control"),
            "configuration_sha256": self.hash(self.run / "iteration-trace-config.xctestrun"),
            "build_provenance_sha256": self.hash(self.run / "refract-build-provenance.json"),
        }
        (self.run / "iteration-trace-config.json").write_text(json.dumps(configuration))
        self.commands = []

    @staticmethod
    def hash(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def export(self, metrics=None, tests=None):
        metrics = synthetic_metrics() if metrics is None else metrics
        tests = synthetic_tests() if tests is None else tests
        def native_export(command, check, capture_output):
            self.assertTrue(check)
            self.assertTrue(capture_output)
            self.commands.append(command)
            payload = tests if " tests " in " ".join(command) else metrics
            return subprocess.CompletedProcess(command, 0, json.dumps(payload).encode(), b"")
        return export_launch_metric(self.run, variant="generated", revision=REVISION, iteration=30,
                                    target_udid=TARGET, run_command=native_export)

    def test_success_retains_raw_selector_commands_and_checksum_bound_scalar(self):
        result = self.export()
        self.assertEqual(result["duration_ms"], 1250.0)
        self.assertEqual(result["path"], "raw/metrics.json")
        self.assertEqual(result["sha256"], self.hash(self.run / "raw/metrics.json"))
        self.assertEqual(self.receipt, json.loads((self.run / "raw/iteration-trace.json").read_text()))
        self.assertEqual(self.receipt["native_first_display"]["timestamp"], "12345.25")
        metrics_command = self.commands[1]
        self.assertEqual(metrics_command[-2:], ["--test-id", IDENTIFIER])
        self.assertIn(str(self.run / "results.xcresult"), metrics_command)
        self.assertFalse(any(command[0] in ("xcodebuild", "xctrace", "simctl") for command in self.commands))
        raw_metrics = json.loads((self.run / "raw/exports/xctest-metrics.json").read_text())
        self.assertEqual(raw_metrics, synthetic_metrics())
        self.assertEqual(json.loads((self.run / "raw/exports/xctest-tests.json").read_text()), synthetic_tests())
        payload = json.loads((self.run / "raw/metrics.json").read_text())
        self.assertEqual(selected_duration(payload, ("generated", "startup", 30), REVISION,
                                           payload["metric_selector"]), 1250.0)
        provenance = payload["provenance"]
        self.assertEqual(payload["measurements"][0]["pid"], NATIVE_PID)
        self.assertEqual(provenance["native_pid"], NATIVE_PID)
        for role, path in self.packet_paths.items():
            self.assertEqual(provenance["native_process_packets"][role], {
                "path": str(path.relative_to(self.run)), "sha256": self.hash(path)})
        self.assertEqual(provenance["native_test_identifier_url"], IDENTIFIER_URL)
        self.assertEqual(provenance["trace_receipt_sha256"], self.hash(self.run / "raw/iteration-trace.json"))
        self.assertEqual(provenance["trace_configuration_receipt_sha256"],
                         self.hash(self.run / "iteration-trace-config.json"))
        for name in ("xctest-tests.json", "xctest-metrics.json"):
            self.assertEqual(provenance["raw_exports"][name]["sha256"], self.hash(self.run / "raw/exports" / name))
        with self.assertRaisesRegex(LaunchMetricError, "Refusing to reuse"):
            self.export()

    def test_missing_invalid_unrelated_and_wrong_typed_pids_fail_before_export(self):
        for role in (*self.packet_paths, "receipt"):
            for marker, value in (("missing", None), ("negative", -1), ("zero", 0),
                                  ("boolean", True), ("float", float(NATIVE_PID)),
                                  ("unrelated", NATIVE_PID + 1)):
                with self.subTest(role=role, marker=marker):
                    case = LaunchMetricExportTest(
                        "test_success_retains_raw_selector_commands_and_checksum_bound_scalar")
                    case.setUp()
                    try:
                        if role == "receipt":
                            if value is None:
                                case.receipt.pop("pid")
                            else:
                                case.receipt["pid"] = value
                            (case.run / "raw/iteration-trace.json").write_text(json.dumps(case.receipt))
                        else:
                            if value is None:
                                case.packets[role].pop("pid")
                            else:
                                case.packets[role]["pid"] = value
                            case.packet_paths[role].write_text(json.dumps(case.packets[role]))
                        with self.assertRaisesRegex(LaunchMetricError, "PID|pid"):
                            case.export()
                        self.assertEqual(case.commands, [])
                        self.assertFalse((case.run / "raw/exports").exists())
                        self.assertFalse((case.run / "raw/metrics.json").exists())
                    finally:
                        case.doCleanups()

    def test_missing_or_stale_native_process_packets_fail_before_export(self):
        for role in self.packet_paths:
            with self.subTest(role=role, change="missing-packet"):
                case = LaunchMetricExportTest(
                    "test_success_retains_raw_selector_commands_and_checksum_bound_scalar")
                case.setUp()
                try:
                    case.packet_paths[role].unlink()
                    with self.assertRaisesRegex(LaunchMetricError, "ordinary retained file"):
                        case.export()
                    self.assertEqual(case.commands, [])
                finally:
                    case.doCleanups()
        for role in self.packet_paths:
            for field, value in (("revision", "b" * 40), ("variant", "reference"),
                                 ("scenario", "scroll"), ("iteration", 29), ("session", 2)):
                with self.subTest(role=role, field=field):
                    case = LaunchMetricExportTest(
                        "test_success_retains_raw_selector_commands_and_checksum_bound_scalar")
                    case.setUp()
                    try:
                        case.packets[role][field] = value
                        case.packet_paths[role].write_text(json.dumps(case.packets[role]))
                        with self.assertRaisesRegex(LaunchMetricError, "packet|iteration"):
                            case.export()
                        self.assertEqual(case.commands, [])
                        self.assertFalse((case.run / "raw/exports").exists())
                    finally:
                        case.doCleanups()

    def test_native_identity_rejection_does_not_clobber_an_existing_metric(self):
        retained = b"existing native metric evidence\n"
        (self.run / "raw/metrics.json").write_bytes(retained)
        self.receipt["pid"] = NATIVE_PID + 1
        (self.run / "raw/iteration-trace.json").write_text(json.dumps(self.receipt))
        with self.assertRaisesRegex(LaunchMetricError, "PID|pid"):
            self.export()
        self.assertEqual(self.commands, [])
        self.assertEqual((self.run / "raw/metrics.json").read_bytes(), retained)
        self.assertFalse((self.run / "raw/exports").exists())

    def test_empty_or_invalid_exports_retain_raw_bytes_but_never_publish_a_duration(self):
        for metrics in ([], synthetic_metrics(metric_changes={"measurements": []}),
                        synthetic_metrics(testIdentifier="RefractBenchUITests/testGeneratedColdStart()")):
            with self.subTest(metrics=metrics):
                root = self.root / f"rejection-{len(list(self.root.iterdir()))}"
                self.run.rename(root)
                self.run = root
                # Relocate the fixture and both archived control-path forms.
                xctestrun_path = self.run / "iteration-trace-config.xctestrun"
                xctestrun = plistlib.loads(xctestrun_path.read_bytes())
                xctestrun["RefractBenchUITests"]["TestingEnvironmentVariables"][
                    "REFRACT_BENCH_TRACE_CONTROL"] = str(self.run / "control")
                xctestrun_path.write_bytes(plistlib.dumps(xctestrun))
                config_path = self.run / "iteration-trace-config.json"
                config = json.loads(config_path.read_text())
                config["control_directory"] = str(self.run / "control")
                config["configuration_sha256"] = self.hash(xctestrun_path)
                config_path.write_text(json.dumps(config))
                with self.assertRaises(LaunchMetricError) as raised:
                    self.export(metrics=metrics)
                self.assertTrue((self.run / "raw/exports/xctest-metrics.json").is_file(),
                                str(raised.exception))
                self.assertFalse((self.run / "raw/metrics.json").exists())

    def test_invalid_retained_paths_and_corrupt_configuration_are_controlled_failures(self):
        file_run = self.root / "not-a-directory"
        file_run.write_text("not a run")
        with self.assertRaisesRegex(LaunchMetricError, "real retained directory"):
            export_launch_metric(file_run, variant="generated", revision=REVISION, iteration=30,
                                 target_udid=TARGET)
        for relative in ("raw/iteration-trace.json", "iteration-trace-config.json",
                         "iteration-trace-config.xctestrun"):
            original = self.run / relative
            replacement = self.root / "replacement"
            original.rename(replacement)
            original.symlink_to(replacement)
            with self.subTest(relative=relative, kind="symlink"), self.assertRaisesRegex(
                    LaunchMetricError, "ordinary retained file"):
                export_launch_metric(self.run, variant="generated", revision=REVISION, iteration=30,
                                     target_udid=TARGET)
            original.unlink()
            replacement.rename(original)
        xctestrun = self.run / "iteration-trace-config.xctestrun"
        original = xctestrun.read_bytes()
        xctestrun.write_bytes(b"not a plist")
        receipt = self.run / "iteration-trace-config.json"
        configuration = json.loads(receipt.read_text())
        configuration["configuration_sha256"] = self.hash(xctestrun)
        receipt.write_text(json.dumps(configuration))
        with self.assertRaisesRegex(LaunchMetricError, "decode|plist"):
            self.export()
        xctestrun.write_bytes(original)

    def test_trace_identity_mismatch_is_rejected_before_export(self):
        for key, value in (("iteration", 2), ("variant", "reference"), ("scenario", "scroll"),
                           ("source_revision", "b" * 40), ("target_udid", "another"),
                           ("device_result", True), ("status", "failed")):
            with self.subTest(key=key, value=value):
                original = self.receipt[key]
                self.receipt[key] = value
                (self.run / "raw/iteration-trace.json").write_text(json.dumps(self.receipt))
                with self.assertRaises(LaunchMetricError):
                    self.export()
                self.assertEqual(self.commands, [])
                self.receipt[key] = original
                (self.run / "raw/iteration-trace.json").write_text(json.dumps(self.receipt))
        for iteration in (0, 1, 31, True, 2.0):
            with self.subTest(iteration=iteration), self.assertRaises(LaunchMetricError):
                export_launch_metric(self.run, variant="generated", revision=REVISION, iteration=iteration,
                                     target_udid=TARGET, run_command=lambda *args, **kwargs: self.fail("exported"))


class TracedStartupSourceTest(unittest.TestCase):
    def test_exact_selectors_measure_one_existing_handshake_not_thirty_new_iterations(self):
        tests = (HERE / "RefractBenchUITests/RefractBenchUITests.swift").read_text()
        helper = tests[tests.index("    private func tracedStartupMetric"):tests.index(
            "    private func launchMetric")]
        self.assertIn("options.iterationCount = 1", helper)
        self.assertIn("measure(metrics: [XCTApplicationLaunchMetric()], options: options)", helper)
        self.assertEqual(helper.count('try runTracedIteration("startup", variant: variant)'), 2)
        self.assertEqual(helper[helper.index("measure(metrics:"):].count(
            'try runTracedIteration("startup", variant: variant)'), 1)
        self.assertIn("var iterationError: Error?", helper)
        self.assertIn("throw iterationError", helper)
        direct = helper[:helper.index("        let options")]
        self.assertIn('environment["REFRACT_BENCH_TRACE_CONTROL"] == nil', direct)
        self.assertIn('try runTracedIteration("startup", variant: variant)', direct)
        self.assertIn("A throwing measure block cannot preserve XCTSkip", direct)
        for variant in ("generated", "reference"):
            body = tests[tests.index(f"    func test{variant.capitalize()}StartupTrace()"):]
            body = body[:body.index("    }")]
            self.assertIn(f'try tracedStartupMetric("{variant}")', body)
        cold_start = tests[tests.index("    private func launchMetric"):tests.index("    private func runScenario")]
        self.assertIn("options.iterationCount = 30", cold_start)
        self.assertNotIn("runTracedIteration", cold_start)
        self.assertEqual(tests.count("options.iterationCount = 1"), 1)
        self.assertEqual(tests.count("options.iterationCount = 30"), 1)
        self.assertNotIn("automaticallyStartMeasuring", tests)
        self.assertNotIn("XCTApplicationLaunchMetric", tests[tests.index("    private func runTracedIteration"):])

    def test_extracted_swift_measures_once_and_propagates_the_existing_helper_error(self):
        swift = os.environ.get("REFRACT_SWIFTC") or shutil.which("swiftc")
        if swift is None:
            self.fail("The focused Swift source regression requires a Swift toolchain")
        tests = (HERE / "RefractBenchUITests/RefractBenchUITests.swift").read_text()
        helper = tests[tests.index("    private func tracedStartupMetric"):tests.index(
            "    private func launchMetric")]
        script = textwrap.dedent("""
            import Foundation
            struct ExpectedError: Error {}
            struct XCTSkip: Error {}
            final class XCTMeasureOptions { var iterationCount: Int = 0 }
            struct XCTApplicationLaunchMetric {}
            var calls = 0
            var measurements = 0
            func runTracedIteration(_ scenario: String, variant: String) throws {
                precondition(scenario == "startup" && variant == "generated")
                calls += 1
                if ProcessInfo.processInfo.environment["REFRACT_BENCH_TRACE_CONTROL"] == nil {
                    throw XCTSkip()
                }
                throw ExpectedError()
            }
            func measure(metrics: [XCTApplicationLaunchMetric], options: XCTMeasureOptions, body: () -> Void) {
                precondition(metrics.count == 1 && options.iterationCount == 1)
                measurements += 1
                body()
            }
            @HELPER@
            do {
                try tracedStartupMetric("generated")
                preconditionFailure("the direct XCTest skip must propagate unchanged")
            } catch is XCTSkip {
                precondition(calls == 1 && measurements == 0,
                             "without a runner, preserve the existing XCTSkip and do not collect metrics")
            }
            calls = 0
            setenv("REFRACT_BENCH_TRACE_CONTROL", "/synthetic-control", 1)
            do {
                try tracedStartupMetric("generated")
                preconditionFailure("the existing traced helper error must not be swallowed")
            } catch is ExpectedError {
                precondition(calls == 1 && measurements == 1,
                             "the exact helper must execute and measure once, not 30 times")
            }
            print("one traced launch measurement, skip and error propagation passed")
            """).lstrip().replace("@HELPER@", helper)
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "main.swift"
            source.write_text(script)
            executable = Path(temporary) / "launch-metric-contract"
            result = subprocess.run([swift, str(source), "-o", str(executable)],
                                    capture_output=True, text=True, timeout=60, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("one traced launch measurement, skip and error propagation passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
