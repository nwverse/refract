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
            "build": {"brand": "google", "device": "emu64xa", "fingerprint": "test", "id": "test-build",
                      "model": model, "version": {"sdk": 35}},
            "device": {"id": "test", "version": 35},
            "compilationMode": "Partial",
            "cpuCoreCount": 2,
            "cpuLocked": False,
            "sustainedPerformanceMode": False,
            "artMainlineVersion": 1,
            "kernelVersion": "test",
            "memTotalBytes": 1,
            "emulator": True,
            "payload": {"refract.sourceRevision": "a" * 40},
        },
    }


def complete_evidence(traces, benchmarks=None):
    return {"traces": traces, "environment": [{"path": "raw/environment.json"}],
            "benchmark_json": benchmarks or [{"path": "raw/001-benchmarkData.json"}]}


def complete_metadata():
    return {"emulator": True, "status": "ready", "source_revision": "a" * 40,
            "source_tree": report.SOURCE_TREE_VERIFIED,
            "benchmark_build_type": "release",
            "compilation_mode": "Partial",
            "macro_iterations": 10,
            "target": {"model": "sdk_gphone64_x86_64", "device": "emu64xa",
                       "build_id": "test-build", "sdk": 35}}


def faithful_trace_filename(variant, scenario, iteration):
    method = {"startup": "Startup", "scroll": "Macrobenchmark[scroll]", "stateUpdate": "StateUpdate"}[scenario]
    # AndroidX 1.4.1 MacrobenchmarkRule uses the simple class name and
    # PerfettoCaptureWrapper appends this exact timestamp format.
    return f"SettingsMacrobenchmark_{variant}{method}_iter{iteration:03d}_2026-01-02-03-04-{iteration:02d}.perfetto-trace"


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
            benchmark("Generated", "scroll", {"memoryRssAnonLastKb": {"runs": [200.0]}}),
            benchmark("Reference", "scroll", {"memoryRssAnonLastKb": {"runs": [100.0]}}),
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

    def complete_macro(self):
        values = []
        traces = []
        for variant in ("Generated", "Reference"):
            for scenario, metrics in (
                # StartupTimingMetric has one raw sample per iteration.
                ("startup", {"timeToInitialDisplayMs": {"runs": [1.0] * 10}}),
                # MemoryUsageMetric(Mode.Last) includes the mode in its key.
                # Frame runs are per-frame samples, not iteration samples.
                ("scroll", {"frameDurationCpuMs": {"runs": [1.0] * 30},
                            "memoryRssAnonLastKb": {"runs": [100.0] * 10}}),
                ("stateUpdate", {"frameDurationCpuMs": {"runs": [1.0] * 24},
                                 "memoryRssAnonLastKb": {"runs": [100.0] * 10}}),
            ):
                value = benchmark(variant, scenario, metrics)
                value["name"] = f"EMULATOR_{value['name']}"
                value["repeatIterations"] = 10
                value["profilerOutputs"] = [{
                    "type": "PerfettoTrace", "label": f"Trace Iteration {iteration}",
                    "filename": faithful_trace_filename(variant.lower(), scenario, iteration),
                } for iteration in range(10)]
                values.append(value)
                traces.extend({
                    "variant": variant.lower(), "scenario": scenario, "iteration": iteration,
                    "androidx_benchmark": value["name"], "androidx_json": "raw/001-benchmarkData.json",
                    "source_name": output["filename"],
                } for iteration, output in enumerate(value["profilerOutputs"]))
        metadata = complete_metadata()
        return values, traces, metadata

    def test_androidx_startup_and_last_memory_keys_complete_macro(self):
        path = Path(self.directory.name) / "input.json"
        values, traces, metadata = self.complete_macro()
        path.write_text(json.dumps(values))
        result = report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                                    evidence=complete_evidence(traces))
        self.assertEqual(result["status"], "pass")
        startup = next(row for row in result["measurements"] if row["benchmark"] == "startup")
        frames = next(row for row in result["measurements"] if row["benchmark"] == "scroll"
                      and row["metric"] == "frameDurationCpuMs")
        memory = next(row for row in result["measurements"] if row["metric"] == "memoryRssAnonLastKb")
        self.assertEqual(startup["sample_count"], 10)
        self.assertEqual(frames["sample_count"], 30)
        self.assertEqual(frames["repeat_iterations"], 10)
        self.assertEqual(memory["sample_count"], 10)
        self.assertEqual(startup["raw_unit"], "ms")
        self.assertEqual(frames["raw_unit"], "ms")
        self.assertEqual(memory["raw_unit"], "Kb")
        for value in values:
            self.assertTrue(value["name"].startswith("EMULATOR_"))
            for iteration, output in enumerate(value["profilerOutputs"]):
                self.assertEqual(output["label"], f"Trace Iteration {iteration}")
                self.assertRegex(output["filename"], r"_iter\d{3}_2026-01-02-03-04-\d{2}\.perfetto-trace$")

    def test_complete_macro_rejects_missing_required_startup_metric(self):
        path = Path(self.directory.name) / "input.json"
        values, traces, metadata = self.complete_macro()
        for value in values:
            if value["name"].endswith("Startup"):
                value["metrics"] = {"startupMs": {"runs": [1.0] * 10}}
        path.write_text(json.dumps(values))
        with self.assertRaisesRegex(report.ReportError, "missing timeToInitialDisplayMs"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                               evidence=complete_evidence(traces))

    def test_complete_macro_rejects_incompatible_startup_units(self):
        path = Path(self.directory.name) / "input.json"
        values, traces, metadata = self.complete_macro()
        path.write_text(json.dumps(values))
        result = report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                                    evidence=complete_evidence(traces))
        startup = {row["variant"]: row for row in result["measurements"]
                   if row["benchmark"] == "startup" and row["metric"] == "timeToInitialDisplayMs"}
        self.assertEqual({variant: row["raw_unit"] for variant, row in startup.items()},
                         {"generated": "ms", "reference": "ms"})

        # Preserve the required AndroidX metric and macro identity, but present
        # an incompatible raw unit at the actual comparison boundary.
        mismatched = [{**startup["generated"], "raw_unit": "s"}, startup["reference"]]
        with self.assertRaisesRegex(report.ReportError,
                                    "Incompatible units for startup.timeToInitialDisplayMs"):
            report.compare_pairs(mismatched, 5.0, 0.1)

    def test_complete_macro_rejects_missing_macro_prefix(self):
        path = Path(self.directory.name) / "input.json"
        values, traces, metadata = self.complete_macro()
        for value in values:
            value["name"] = value["name"].removeprefix("EMULATOR_")
        for trace in traces:
            trace["androidx_benchmark"] = trace["androidx_benchmark"].removeprefix("EMULATOR_")
        path.write_text(json.dumps(values))
        with self.assertRaisesRegex(report.ReportError, "missing AndroidX EMULATOR_ prefix"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                               evidence=complete_evidence(traces))

    def test_complete_macro_requires_all_scenarios_raw_metrics_and_traces(self):
        path = Path(self.directory.name) / "input.json"
        values, trace_coverage, metadata = self.complete_macro()
        path.write_text(json.dumps(values))
        result = report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                                    evidence=complete_evidence(trace_coverage))
        self.assertEqual(result["status"], "pass")
        self.assertEqual(result["artifact_integrity"], "verified")
        self.assertTrue(result["macro_evidence_required"])

        incomplete = values[:-1]
        path.write_text(json.dumps(incomplete))
        with self.assertRaisesRegex(report.ReportError, "missing reference.stateUpdate"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                               evidence=complete_evidence(trace_coverage[:-10]))
        path.write_text(json.dumps(values))
        with self.assertRaisesRegex(report.ReportError, "one trace for every declared iteration"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                               evidence=complete_evidence(trace_coverage[:-1]))
        for value in values:
            value["profilerOutputs"] = []
        path.write_text(json.dumps(values))
        with self.assertRaisesRegex(report.ReportError, "AndroidX JSON has no Perfetto filename"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                               evidence=complete_evidence(trace_coverage))

    def test_macro_target_identity_must_match_probe(self):
        path = Path(self.directory.name) / "input.json"
        values, traces, metadata = self.complete_macro()
        path.write_text(json.dumps(values))
        for key, value in (("model", "other-model"), ("device", "other-device"),
                           ("build_id", "other-build"), ("sdk", 34)):
            changed = complete_metadata()
            changed["target"][key] = value
            with self.subTest(key=key), self.assertRaisesRegex(report.ReportError, "target/build identity"):
                report.make_report([path], 5.0, 0.1, changed, require_macro=True,
                                   evidence=complete_evidence(traces))

    def test_macro_source_provenance_must_match_androidx_payload(self):
        path = Path(self.directory.name) / "input.json"
        values, traces, metadata = self.complete_macro()
        for value in values:
            value["context"] = {**value["context"], "payload": {"refract.sourceRevision": "b" * 40}}
        path.write_text(json.dumps(values))
        with self.assertRaisesRegex(report.ReportError, "source provenance"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                               evidence=complete_evidence(traces))
        for value in values:
            value["context"] = {**value["context"], "payload": {}}
        path.write_text(json.dumps(values))
        with self.assertRaisesRegex(report.ReportError, "source provenance"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                               evidence=complete_evidence(traces))

    def test_macro_rejects_missing_or_dirty_source_attestation(self):
        path = Path(self.directory.name) / "input.json"
        values, traces, metadata = self.complete_macro()
        path.write_text(json.dumps(values))
        for change in ({"source_tree": "dirty"}, {"source_tree": None}, {"status": "blocked"}):
            changed = {**metadata, **change}
            with self.subTest(change=change), self.assertRaisesRegex(report.ReportError, "clean source tree"):
                report.make_report([path], 5.0, 0.1, changed, require_macro=True,
                                   evidence=complete_evidence(traces))
        with self.assertRaisesRegex(report.ReportError, "dedicated preserved environment"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                               evidence={"traces": traces, "environment": []})

    def test_macro_requires_initial_display_and_exact_iteration_samples(self):
        path = Path(self.directory.name) / "input.json"
        values, traces, metadata = self.complete_macro()
        for value in values:
            if value["name"].endswith("Startup"):
                value["metrics"] = {"timeToFullDisplayMs": {"runs": [1.0] * 10}}
        path.write_text(json.dumps(values))
        with self.assertRaisesRegex(report.ReportError, "missing timeToInitialDisplayMs"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                               evidence=complete_evidence(traces))
        values, traces, metadata = self.complete_macro()
        for value in values:
            if value["name"].endswith("Startup"):
                value["metrics"]["timeToInitialDisplayMs"]["runs"] = [1.0] * 11
        path.write_text(json.dumps(values))
        with self.assertRaisesRegex(report.ReportError, "one raw startup sample per declared iteration"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                               evidence=complete_evidence(traces))

    def test_macro_rejects_short_or_aggregate_runs_and_missing_memory(self):
        path = Path(self.directory.name) / "input.json"
        for scenario, metrics, error in (
            ("startup", {"timeToInitialDisplayMs": {"minimum": 1.0, "maximum": 2.0, "median": 1.0}}, "raw samples"),
            ("scroll", {"frameDurationCpuMs": {"runs": [1.0] * 30}}, "missing memory"),
        ):
            values, trace_coverage, metadata = self.complete_macro()
            for value in values:
                if value["name"].endswith(scenario.capitalize()) or scenario == "scroll" \
                        and value["name"].endswith("Macrobenchmark.scroll"):
                    value["metrics"] = metrics
            path.write_text(json.dumps(values))
            with self.subTest(scenario=scenario), self.assertRaisesRegex(report.ReportError, error):
                report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                                   evidence=complete_evidence(trace_coverage))

    def test_macro_rejects_invalid_trace_identity_bindings(self):
        path = Path(self.directory.name) / "input.json"
        values, traces, metadata = self.complete_macro()
        path.write_text(json.dumps(values))
        invalid = complete_evidence([{**trace, "androidx_benchmark": "wrongBenchmark"}
                                    for trace in traces])
        with self.assertRaisesRegex(report.ReportError, "retained AndroidX benchmark"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True, evidence=invalid)
        invalid = complete_evidence([{**trace, "androidx_json": "raw/wrong.json"}
                                    for trace in traces])
        with self.assertRaisesRegex(report.ReportError, "retained AndroidX benchmark"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True, evidence=invalid)
        invalid = complete_evidence([{**trace, "iteration": 0} for trace in traces])
        with self.assertRaisesRegex(report.ReportError, "duplicate iteration binding"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True, evidence=invalid)
        invalid = complete_evidence([{**trace, "scenario": "stateUpdate" if trace["scenario"] == "scroll"
                                       else trace["scenario"]} for trace in traces])
        with self.assertRaisesRegex(report.ReportError, "contradicts its AndroidX benchmark identity"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True, evidence=invalid)
        invalid = complete_evidence([{**trace, "iteration": "0"} for trace in traces])
        with self.assertRaisesRegex(report.ReportError, "invalid iteration binding"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True, evidence=invalid)

    def test_macro_rejects_cross_json_trace_ownership(self):
        root = Path(self.directory.name)
        values, traces, metadata = self.complete_macro()
        paths = []
        for index, variant in enumerate(("generated", "reference"), 1):
            path = root / f"raw/{index:03d}-benchmarkData.json"
            path.parent.mkdir(exist_ok=True)
            selected = [value for value in values if f"SettingsMacrobenchmark.{variant}" in value["name"]]
            path.write_text(json.dumps({"context": selected[0]["context"], "benchmarks": selected}))
            paths.append(path)
            for trace in traces:
                if trace["variant"] == variant:
                    trace["androidx_json"] = f"raw/{index:03d}-benchmarkData.json"
        evidence = complete_evidence(traces, [
            {"path": f"raw/{index:03d}-benchmarkData.json"} for index in (1, 2)
        ])
        result = report.make_report(paths, 5.0, 0.1, metadata, require_macro=True,
                                    evidence=evidence, output=root)
        self.assertEqual(result["status"], "pass")

        crossed = [dict(trace) for trace in evidence["traces"]]
        for trace in crossed:
            trace["androidx_json"] = "raw/002-benchmarkData.json" \
                if trace["variant"] == "generated" else "raw/001-benchmarkData.json"
        with self.assertRaisesRegex(report.ReportError, "source AndroidX JSON"):
            report.make_report(paths, 5.0, 0.1, metadata, require_macro=True,
                               evidence=complete_evidence(crossed, evidence["benchmark_json"]), output=root)

    def test_macro_rejects_a_trace_not_named_by_androidx(self):
        path = Path(self.directory.name) / "input.json"
        values, traces, metadata = self.complete_macro()
        path.write_text(json.dumps(values))
        invalid = complete_evidence([{**trace, "source_name": "substituted.perfetto-trace"}
                                    for trace in traces])
        with self.assertRaisesRegex(report.ReportError, "AndroidX profiler output"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True, evidence=invalid)

    def test_macro_rejects_incomplete_iteration_samples_and_traces(self):
        path = Path(self.directory.name) / "input.json"
        values, traces, metadata = self.complete_macro()
        for value in values:
            if value["name"].endswith("Macrobenchmark.scroll"):
                value["metrics"]["memoryRssAnonLastKb"]["runs"] = [100.0]
        path.write_text(json.dumps(values))
        with self.assertRaisesRegex(report.ReportError, "one memory sample per declared iteration"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True, evidence=complete_evidence(traces))
        for value in values:
            if value["name"].endswith("Macrobenchmark.scroll"):
                value["metrics"]["memoryRssAnonLastKb"]["runs"] = [100.0] * 10
        path.write_text(json.dumps(values))
        with self.assertRaisesRegex(report.ReportError, "one trace for every declared iteration"):
            report.make_report([path], 5.0, 0.1, metadata, require_macro=True,
                               evidence=complete_evidence([trace for trace in traces if trace["iteration"] != 1]))

    def test_macro_requires_probe_revision(self):
        path = Path(self.directory.name) / "input.json"
        path.write_text(json.dumps([benchmark("Generated"), benchmark("Reference")]))
        with self.assertRaisesRegex(report.ReportError, "full source revision"):
            report.make_report([path], 5.0, 0.1, require_macro=True)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)


if __name__ == "__main__":
    unittest.main()
