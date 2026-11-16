import importlib.util
import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("report", Path(__file__).with_name("report.py"))
report = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = report
assert SPEC.loader is not None
SPEC.loader.exec_module(report)


def benchmark(variant, scenario="scroll", metrics=None, model="sdk_gphone64_x86_64"):
    kind = "Micro" if scenario == "rowRecomposition" else "Macro"
    method = {
        ("Macro", "scroll"): f"{variant.lower()}Macrobenchmark",
        ("Macro", "startup"): f"{variant.lower()}Startup",
        ("Macro", "stateUpdate"): f"{variant.lower()}StateUpdate",
        ("Micro", "rowRecomposition"): f"{variant.lower()}RowRecomposition",
    }[(kind, scenario)]
    name = f"dev.refract.bench.test.Settings{kind}benchmark.{method}"
    if scenario == "scroll":
        name += ".scroll"
    return {
        "name": name,
        "params": {},
        "className": f"dev.refract.bench.test.Settings{kind}benchmark",
        "totalRunTimeNs": 1000000,
        "metrics": metrics or {"frameDurationCpuMs": {"runs": [10.0, 20.0, 30.0]}},
        "sampledMetrics": {},
        "warmupIterations": 0,
        "repeatIterations": 3,
        "thermalThrottleSleepSeconds": 0,
        "context": {
            "build": {"brand": "google", "device": "emu64xa", "fingerprint": "test", "model": model, "version": {"sdk": 35}},
            "device": {"id": "test", "version": 35},
            "compilationMode": "Partial",
            "cpuCoreCount": 2,
            "cpuLocked": False,
            "sustainedPerformanceMode": False,
            "artMainlineVersion": 1,
            "kernelVersion": "test",
            "memTotalBytes": 1,
            "emulator": True,
        },
    }


class ReportTest(unittest.TestCase):
    def test_percentile_is_nearest_rank(self):
        self.assertEqual(report.percentile([3.0, 1.0, 2.0], 0.5), 2)
        self.assertEqual(report.percentile([3.0, 1.0, 2.0], 0.99), 3)

    def test_valid_pair_reports_p50_p99_and_emulator(self):
        path = Path(self.directory.name) / "input.json"
        path.write_text(json.dumps([benchmark("Generated"), benchmark("Reference")]))
        result = report.make_report([path], 5.0, 0.1)
        self.assertEqual(result["status"], "pass")
        self.assertEqual(result["environment_label"], "emulator")
        self.assertFalse(result["device_result"])
        self.assertEqual(result["measurements"][0]["samples"], [10.0, 20.0, 30.0])

    def test_p99_regression_fails(self):
        path = Path(self.directory.name) / "input.json"
        values = [10.0] * 98 + [20.0, 100.0]
        path.write_text(json.dumps([
            benchmark("Generated", "scroll", {"frameDurationCpuMs": {"runs": [11.0] * 98 + [21.0, 101.0]}}),
            benchmark("Reference", "scroll", {"frameDurationCpuMs": {"runs": values}}),
        ]))
        result = report.make_report([path], 5.0, 0.1)
        self.assertEqual(result["status"], "fail")

    def test_small_absolute_noise_is_not_failure(self):
        path = Path(self.directory.name) / "input.json"
        path.write_text(json.dumps([
            benchmark("Generated", "startup", {"startupMs": {"runs": [0.104]}}),
            benchmark("Reference", "startup", {"startupMs": {"runs": [0.1]}}),
        ]))
        self.assertEqual(report.make_report([path], 5.0, 0.1)["status"], "pass")

    def test_both_noise_conditions_are_required(self):
        path = Path(self.directory.name) / "input.json"
        path.write_text(json.dumps([
            benchmark("Generated", "startup", {"startupMs": {"runs": [104.0]}}),
            benchmark("Reference", "startup", {"startupMs": {"runs": [100.0]}}),
        ]))
        self.assertEqual(report.make_report([path], 5.0, 0.1)["status"], "pass")

    def test_nanoseconds_are_normalized(self):
        path = Path(self.directory.name) / "input.json"
        path.write_text(json.dumps([
            benchmark("Generated", "rowRecomposition", {"timeNs": {"runs": [12_000_000.0]}}),
            benchmark("Reference", "rowRecomposition", {"timeNs": {"runs": [1_000_000.0]}}),
        ]))
        result = report.make_report([path], 5.0, 0.1)
        self.assertEqual(result["comparisons"][0]["metric"], "timeMs")
        self.assertEqual(result["status"], "fail")

    def test_missing_pair_is_an_error(self):
        path = Path(self.directory.name) / "input.json"
        path.write_text(json.dumps([benchmark("Generated")]))
        with self.assertRaisesRegex(report.ReportError, "Expected one reference"):
            report.make_report([path], 5.0, 0.1)

    def test_different_environment_is_an_error(self):
        path = Path(self.directory.name) / "input.json"
        path.write_text(json.dumps([
            benchmark("Generated", model="sdk_one"),
            benchmark("Reference", model="sdk_two"),
        ]))
        with self.assertRaisesRegex(report.ReportError, "different devices"):
            report.make_report([path], 5.0, 0.1)

    def test_invalid_runs_are_an_error(self):
        path = Path(self.directory.name) / "input.json"
        path.write_text(json.dumps([
            benchmark("Generated", "scroll", {"frameDurationCpuMs": {"runs": []}}),
            benchmark("Reference"),
        ]))
        with self.assertRaisesRegex(report.ReportError, "finite numeric runs"):
            report.make_report([path], 5.0, 0.1)

    def test_zero_baseline_cannot_hide_regression(self):
        path = Path(self.directory.name) / "input.json"
        path.write_text(json.dumps([
            benchmark("Generated", "startup", {"startupMs": {"runs": [1.0]}}),
            benchmark("Reference", "startup", {"startupMs": {"runs": [0.0]}}),
        ]))
        result = report.make_report([path], 5.0, 0.1)
        self.assertEqual(result["status"], "fail")
        self.assertTrue(math.isinf(result["comparisons"][0]["p50"]["percent"]))

    def test_missing_scenario_is_an_error(self):
        path = Path(self.directory.name) / "input.json"
        path.write_text(json.dumps([
            benchmark("Generated"),
            benchmark("Reference"),
            benchmark("Generated", "startup", {"startupMs": {"runs": [1.0]}}),
        ]))
        with self.assertRaisesRegex(report.ReportError, "Expected one reference"):
            report.make_report([path], 5.0, 0.1)

    def test_nonfinite_values_are_rejected(self):
        path = Path(self.directory.name) / "input.json"
        path.write_text('[{"name": NaN}]')
        with self.assertRaisesRegex(report.ReportError, "Non-finite"):
            report.make_report([path], 5.0, 0.1)

    def test_missing_emulator_label_is_rejected(self):
        path = Path(self.directory.name) / "input.json"
        generated = benchmark("Generated")
        reference = benchmark("Reference")
        for value in (generated, reference):
            value["context"].pop("emulator")
        path.write_text(json.dumps([generated, reference]))
        with self.assertRaisesRegex(report.ReportError, "verified emulator"):
            report.make_report([path], 5.0, 0.1, {"emulator": False})

    def test_aggregate_only_micro_result_has_no_p99_gate(self):
        metrics = {"timeNs": {"minimum": 1.0, "maximum": 2.0, "median": 1.0}}
        path = Path(self.directory.name) / "input.json"
        path.write_text(json.dumps([
            benchmark("Generated", "rowRecomposition", metrics),
            benchmark("Reference", "rowRecomposition", metrics),
        ]))
        result = report.make_report([path], 5.0, 0.1)
        self.assertEqual(result["measurements"][0]["sample_kind"], "aggregate")
        self.assertNotIn("p99", result["comparisons"][0])
        self.assertEqual(result["measurements"][0]["sample_count"], 1)
        self.assertEqual(result["measurements"][0]["repeat_iterations"], 3)

    def test_memory_does_not_use_millisecond_threshold(self):
        path = Path(self.directory.name) / "input.json"
        path.write_text(json.dumps([
            benchmark("Generated", "scroll", {"memoryRssAnonKb": {"runs": [200.0]}}),
            benchmark("Reference", "scroll", {"memoryRssAnonKb": {"runs": [100.0]}}),
        ]))
        result = report.make_report([path], 5.0, 0.1)
        self.assertNotIn("p50", result["comparisons"][0])

    def test_complete_four_scenario_pairs_pass(self):
        path = Path(self.directory.name) / "input.json"
        values = []
        for variant in ("Generated", "Reference"):
            for scenario, metrics in (
                ("startup", {"startupMs": {"runs": [1.0]}}),
                ("scroll", {"frameDurationCpuMs": {"runs": [1.0]}}),
                ("stateUpdate", {"frameDurationCpuMs": {"runs": [1.0]}}),
                ("rowRecomposition", {"timeNs": {"runs": [1_000_000.0]}}),
            ):
                values.append(benchmark(variant, scenario, metrics))
        path.write_text(json.dumps(values))
        self.assertEqual(report.make_report([path], 5.0, 0.1)["status"], "pass")

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)


if __name__ == "__main__":
    unittest.main()
