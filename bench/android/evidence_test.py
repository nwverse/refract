import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


probe_target = load("probe_target")
collect_results = load("collect_results")
report = load("report")
report_test = load("report_test")


REVISION = "a" * 40


def complete_androidx_benchmarks(iterations=10):
    values = []
    for variant in ("Generated", "Reference"):
        for scenario, metrics in (
            ("startup", {"timeToInitialDisplayMs": {"runs": [1.0] * 10}}),
            ("scroll", {"frameDurationCpuMs": {"runs": [1.0] * 30},
                        "memoryRssAnonLastKb": {"runs": [100.0] * 10}}),
            ("stateUpdate", {"frameDurationCpuMs": {"runs": [1.0] * 24},
                             "memoryRssAnonLastKb": {"runs": [100.0] * 10}}),
        ):
            value = report_test.benchmark(variant, scenario, metrics)
            value["name"] = f"EMULATOR_{value['name']}"
            value["profilerOutputs"] = [{
                "type": "PerfettoTrace", "label": f"Trace Iteration {iteration}",
                "filename": faithful_trace_filename(variant.lower(), scenario, iteration),
            } for iteration in range(iterations)]
            values.append(value)
    for value in values:
        value["repeatIterations"] = iterations
    return values


faithful_trace_filename = report_test.faithful_trace_filename


def properties(**changes):
    values = {
        "ro.product.model": "Stable test target",
        "ro.product.device": "test_device",
        "ro.build.version.release": "15",
        "ro.build.version.sdk": "35",
        "ro.build.display.id": "test-build",
        "ro.build.type": "userdebug",
        "ro.product.cpu.abi": "x86_64",
        "ro.kernel.qemu": "1",
        "sys.boot_completed": "1",
        "ro.hardware.egl": "test",
        "ro.hardware.vulkan": "test",
        "ro.opengles.version": "196610",
        "qemu.gles": "1",
        "debug.sf.hw": "1",
    }
    values.update(changes)
    return values


class TargetProbeTest(unittest.TestCase):
    def test_no_target_is_a_blocker_without_a_boot_action(self):
        with self.assertRaisesRegex(probe_target.ProbeError, "no target was started"):
            probe_target.select_target("List of devices attached\n\n", None)

    def test_explicit_target_must_be_connected(self):
        with self.assertRaisesRegex(probe_target.ProbeError, "not attached"):
            probe_target.select_target("List of devices attached\nother\tdevice\n", "selected")

    def test_offline_target_is_rejected(self):
        with self.assertRaisesRegex(probe_target.ProbeError, "not in the device state"):
            probe_target.select_target("List of devices attached\ntarget\toffline\n", None)

    def test_valid_metadata_names_emulator_and_revision(self):
        result = probe_target.inspect(properties(), "emulated;0 mounted\n", REVISION)
        self.assertTrue(result["emulator"])
        self.assertFalse(result["device_result"])
        self.assertEqual(result["source_revision"], REVISION)
        self.assertEqual(result["macro_iterations"], 10)
        self.assertEqual(result["target"]["sdk"], 35)
        self.assertIn("qemu.gles", result["rendering"])

    def test_unmounted_storage_is_rejected(self):
        for state in ("unmountable", "checking", "ejecting"):
            with self.subTest(state=state), self.assertRaisesRegex(probe_target.ProbeError, "no mounted"):
                probe_target.inspect(properties(), f"emulated;0 {state}\n", REVISION)

    def test_incomplete_boot_and_unverified_device_are_rejected(self):
        with self.assertRaisesRegex(probe_target.ProbeError, "not completed boot"):
            probe_target.inspect(properties(**{"sys.boot_completed": "0"}), "emulated;0 mounted", REVISION)
        with self.assertRaisesRegex(probe_target.ProbeError, "explicitly identified emulator"):
            probe_target.inspect(properties(**{"ro.kernel.qemu": "0"}), "emulated;0 mounted", REVISION)

    def test_probe_does_not_start_or_modify_target(self):
        adb = mock.Mock()
        responses = {
            ("devices",): "List of devices attached\ntarget\tdevice\n",
            ("shell", "sm", "list-volumes", "all"): "emulated;0 mounted",
        }
        for key in probe_target.PROPERTIES:
            responses[("shell", "getprop", key)] = properties()[key]
        for service in probe_target.SERVICES:
            responses[("shell", "service", "check", service)] = f"Service {service}: found"
        responses[("shell", f"mkdir -p '{probe_target.OUTPUT_ROOT}' && test -w '{probe_target.OUTPUT_ROOT}'")] = ""
        adb.call.side_effect = lambda arguments, serial=None: responses[tuple(arguments)]
        result = probe_target.probe(adb, None, REVISION)
        self.assertEqual(result["status"], "ready")
        self.assertEqual(result["android_serial"], "target")
        commands = [call.args[0] for call in adb.call.call_args_list]
        self.assertFalse(any(command[0] in ("emu", "root", "reboot") for command in commands))


class EvidenceCollectionTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.inputs = self.root / "androidx-output"
        self.output = self.root / "run"
        self.inputs.mkdir()
        self.environment = self.root / "environment.json"
        self.environment.write_text(json.dumps({
            "status": "ready", "emulator": True, "source_revision": REVISION,
        }))

    def write_environment(self):
        environment = self.output / "environment.json"
        metadata = report_test.complete_metadata()
        metadata["source_revision"] = REVISION
        environment.write_text(json.dumps(metadata))
        return environment

    def collect(self):
        return collect_results.collect(self.inputs, self.output, self.environment)

    def add_json(self, name="benchmarkData.json", benchmarks=None, declared_iterations=10):
        path = self.inputs / name
        if benchmarks is None:
            benchmarks = complete_androidx_benchmarks(declared_iterations)
        for value in benchmarks:
            value.pop("context", None)
        document = {"context": report_test.benchmark("Generated")["context"], "benchmarks": benchmarks}
        document["context"]["payload"] = {"refract.sourceRevision": REVISION}
        path.write_text(json.dumps(document))
        return path

    def write_json(self, benchmarks, revision=REVISION):
        source = self.inputs / "benchmarkData.json"
        source.write_text(json.dumps({"context": {"payload": {"refract.sourceRevision": revision}},
                                     "benchmarks": benchmarks}))

    def add_traces(self, iterations=10):
        for variant in ("generated", "reference"):
            for scenario in ("startup", "scroll", "stateUpdate"):
                for iteration in range(iterations):
                    filename = faithful_trace_filename(variant, scenario, iteration)
                    (self.inputs / filename).write_bytes(b"trace")

    def test_copies_json_and_all_six_perfetto_scenarios(self):
        self.add_json()
        self.add_traces()
        manifest = collect_results.collect(self.inputs, self.output, self.environment)
        self.assertEqual(len(manifest["benchmark_json"]), 1)
        self.assertEqual(len(manifest["traces"]), 60)
        self.assertEqual(len(manifest["environment"]), 1)
        self.assertTrue(all(item["variant"] and item["scenario"] for item in manifest["traces"]))
        self.assertTrue(all(item["androidx_benchmark"] for item in manifest["traces"]))
        for item in manifest["traces"]:
            self.assertIn("_2026-01-02-03-04-", item["source_name"])
            self.assertFalse(item["source_name"].startswith("dev.refract.bench.test."))
        self.assertEqual(collect_results.trace_identity("Class_generatedMacrobenchmark[scroll]"), ("generated", "scroll"))
        for item in manifest["traces"]:
            self.assertEqual((self.output / item["path"]).read_bytes(), b"trace")
        verified = report.verify_evidence(manifest, self.output, [self.output / "raw/001-benchmarkData.json"])
        self.assertEqual(len(verified["traces"]), 60)

    def test_ten_timestamped_androidx_iterations_bind_exact_relative_paths(self):
        benchmarks = complete_androidx_benchmarks()
        for value in benchmarks:
            if value["name"] == "EMULATOR_dev.refract.bench.test.SettingsMacrobenchmark.generatedMacrobenchmark.scroll":
                value["profilerOutputs"] = [{
                    "type": "PerfettoTrace", "label": f"Trace Iteration {iteration}",
                    "filename": f"generatedMacrobenchmark[scroll]_iter{iteration:03d}_2026-01-02-03-04-{iteration:02d}.perfetto-trace",
                } for iteration in range(10)]
        self.add_json(benchmarks=benchmarks)
        self.add_traces(iterations=10)
        for iteration in range(10):
            filename = f"generatedMacrobenchmark[scroll]_iter{iteration:03d}_2026-01-02-03-04-{iteration:02d}.perfetto-trace"
            (self.inputs / faithful_trace_filename("generated", "scroll", iteration)).unlink()
            (self.inputs / filename).write_bytes(b"trace")
        manifest = collect_results.collect(self.inputs, self.output, self.environment)
        traces = [trace for trace in manifest["traces"] if trace["scenario"] == "scroll"
                  and trace["variant"] == "generated" and "generatedMacrobenchmark[scroll]" in trace["source_name"]]
        self.assertEqual([trace["iteration"] for trace in traces], list(range(10)))

    def test_provenance_mismatch_duplicate_keys_and_changed_environment_fail(self):
        for state, error in (
            ({"status": "ready", "emulator": True, "source_revision": "b" * 40}, "source payload"),
            (None, "Duplicate evidence JSON key"),
        ):
            self.add_json()
            self.add_traces()
            if state is None:
                self.environment.write_text('{"status":"ready","status":"ready"}')
            else:
                self.environment.write_text(json.dumps(state))
            with self.subTest(error=error), self.assertRaisesRegex(collect_results.EvidenceError, error):
                collect_results.collect(self.inputs, self.output, self.environment)
            self.output = self.root / f"run-{error.replace(' ', '-')}"

        self.output = self.root / "run-valid"
        self.add_json()
        self.add_traces()
        self.environment.write_text(json.dumps({
            "status": "ready", "emulator": True, "source_revision": REVISION,
            "source_tree": report.SOURCE_TREE_VERIFIED,
        }))
        collect_results.collect(self.inputs, self.output, self.environment)
        (self.output / "raw/environment.json").write_text('{"emulator":true}')
        arguments = ["--output", str(self.output), "--require-macro",
                     "--evidence-manifest", str(self.output / "evidence-manifest.json"),
                     str(self.output / "raw/001-benchmarkData.json")]
        self.assertEqual(report.main(arguments), 2)
        with self.assertRaisesRegex(report.ReportError, "Duplicate JSON key"):
            report.load_json(self._duplicate_json())

    def _duplicate_json(self):
        path = self.inputs / "duplicate-key.json"
        path.write_text('{"refract.sourceRevision":"a","refract.sourceRevision":"b"}')
        return path

    def test_duplicate_macro_scenario_cannot_replace_a_missing_pair(self):
        document = json.loads(self.add_json().read_text())
        document["benchmarks"][-1] = document["benchmarks"][0]
        self.write_json(document["benchmarks"])
        self.add_traces()
        with self.assertRaisesRegex(collect_results.EvidenceError, "Duplicate or unidentified"):
            collect_results.collect(self.inputs, self.output, self.environment)

    def test_json_is_required(self):
        with self.assertRaisesRegex(collect_results.EvidenceError, "No AndroidX"):
            collect_results.collect(self.inputs, self.output, self.environment)

    def test_missing_or_unreferenced_trace_is_rejected(self):
        payload = json.loads(self.add_json().read_text())["benchmarks"]
        payload[0]["profilerOutputs"][0]["filename"] = "missing.perfetto-trace"
        self.write_json(payload)
        self.add_traces()
        with self.assertRaisesRegex(collect_results.EvidenceError, "missing or ambiguous"):
            collect_results.collect(self.inputs, self.output, self.environment)

    def test_unreferenced_trace_is_rejected(self):
        self.add_json()
        self.add_traces()
        (self.inputs / "unreferenced_2026-01-02-03-04-05.perfetto-trace").write_bytes(b"extra")
        with self.assertRaisesRegex(collect_results.EvidenceError, "not referenced"):
            collect_results.collect(self.inputs, self.output, self.environment)

    def test_misassigned_trace_cannot_satisfy_another_iteration(self):
        payload = json.loads(self.add_json().read_text())["benchmarks"]
        payload[0]["profilerOutputs"][1]["filename"] = payload[0]["profilerOutputs"][0]["filename"]
        self.write_json(payload)
        self.add_traces(iterations=10)
        with self.assertRaisesRegex(collect_results.EvidenceError, "multiple benchmark iterations"):
            collect_results.collect(self.inputs, self.output, self.environment)

    def test_duplicate_relative_filename_is_ambiguous(self):
        source = self.add_json()
        payload = json.loads(source.read_text())["benchmarks"]
        filename = Path(payload[0]["profilerOutputs"][0]["filename"]).name
        payload[0]["profilerOutputs"][0]["filename"] = filename
        self.write_json(payload)
        (self.inputs / filename).write_bytes(b"trace")
        (self.inputs / "duplicate").mkdir()
        (self.inputs / "duplicate" / filename).write_bytes(b"trace")
        with self.assertRaisesRegex(collect_results.EvidenceError, "missing or ambiguous"):
            collect_results.collect(self.inputs, self.output, self.environment)

    def test_trace_path_cannot_escape_output_directory(self):
        source = self.add_json()
        payload = json.loads(source.read_text())["benchmarks"]
        payload[0]["profilerOutputs"][0]["filename"] = "../outside.perfetto-trace"
        self.write_json(payload)
        self.add_traces()
        with self.assertRaisesRegex(collect_results.EvidenceError, "escapes"):
            collect_results.collect(self.inputs, self.output, self.environment)

    def test_ten_declared_iterations_require_ten_distinct_traces(self):
        self.add_json()
        self.add_traces(iterations=1)
        with self.assertRaisesRegex(collect_results.EvidenceError, "missing or ambiguous"):
            collect_results.collect(self.inputs, self.output, self.environment)

    def test_duplicate_iteration_label_cannot_fill_a_missing_iteration(self):
        payload = json.loads(self.add_json().read_text())["benchmarks"]
        payload[0]["profilerOutputs"][1] = payload[0]["profilerOutputs"][0]
        self.write_json(payload)
        self.add_traces(iterations=10)
        with self.assertRaisesRegex(collect_results.EvidenceError, "every declared iteration"):
            collect_results.collect(self.inputs, self.output, self.environment)

    def test_macro_without_profiler_outputs_cannot_pass(self):
        payload = json.loads(self.add_json().read_text())["benchmarks"]
        payload[0]["profilerOutputs"] = []
        self.write_json(payload)
        self.add_traces()
        with self.assertRaisesRegex(collect_results.EvidenceError, "no profilerOutputs"):
            collect_results.collect(self.inputs, self.output, self.environment)

    def test_failed_collection_publishes_no_manifest_or_raw_artifacts(self):
        payload = json.loads(self.add_json().read_text())["benchmarks"]
        payload[0]["profilerOutputs"][0]["filename"] = "missing.perfetto-trace"
        self.write_json(payload)
        self.add_traces()
        with self.assertRaisesRegex(collect_results.EvidenceError, "missing or ambiguous"):
            collect_results.collect(self.inputs, self.output, self.environment)
        self.assertFalse((self.output / "evidence-manifest.json").exists())
        self.assertFalse((self.output / "json-files.txt").exists())
        self.assertFalse((self.output / "raw").exists())
        staging = list(self.output.glob(".evidence-staging-*"))
        self.assertEqual(len(staging), 1)
        self.assertFalse((staging[0] / "evidence-manifest.json").exists())

    def test_existing_evidence_is_not_modified_by_a_rejected_recollection(self):
        self.add_json()
        self.add_traces()
        manifest = collect_results.collect(self.inputs, self.output, self.environment)
        environment_path = self.output / "raw/environment.json"
        before = environment_path.read_bytes()
        self.add_json()
        self.add_traces()
        with self.assertRaisesRegex(collect_results.EvidenceError, "Refusing to replace"):
            collect_results.collect(self.inputs, self.output, self.environment)
        self.assertEqual(environment_path.read_bytes(), before)
        report.verify_evidence(manifest, self.output, [self.output / "raw/001-benchmarkData.json"],
                               require_environment=True)

    def test_checksum_mismatch_and_wrong_input_are_rejected(self):
        source = self.add_json()
        self.add_traces()
        manifest = collect_results.collect(self.inputs, self.output, self.environment)
        copied = self.output / "raw/001-benchmarkData.json"
        copied.write_text("changed")
        with self.assertRaisesRegex(report.ReportError, "checksum mismatch"):
            report.verify_evidence(manifest, self.output, [copied])
        copied.write_bytes(source.read_bytes())
        report.verify_evidence(manifest, self.output, [copied])
        with self.assertRaisesRegex(report.ReportError, "exactly match"):
            report.verify_evidence(manifest, self.output, [source])

    def test_empty_trace_is_rejected_without_changing_the_manifest(self):
        self.add_json()
        self.add_traces()
        manifest = collect_results.collect(self.inputs, self.output, self.environment)
        trace = self.output / manifest["traces"][0]["path"]
        trace.write_bytes(b"")
        self.assertEqual(manifest["traces"][0]["bytes"], 5)
        with self.assertRaisesRegex(report.ReportError, "checksum mismatch"):
            report.verify_evidence(manifest, self.output,
                                   [self.output / "raw/001-benchmarkData.json"])

    def test_complete_macro_cli_verifies_preserved_evidence(self):
        source = self.add_json()
        self.add_traces()
        self.output.mkdir()
        environment = self.write_environment()
        collect_results.collect(self.inputs, self.output, environment)
        arguments = ["--output", str(self.output),
                     "--require-macro", "--evidence-manifest", str(self.output / "evidence-manifest.json"),
                     str(self.output / "raw/001-benchmarkData.json")]
        self.assertEqual(report.main(arguments), 0)
        result = json.loads((self.output / "report.json").read_text())
        self.assertTrue(result["macro_evidence_required"])
        self.assertEqual(result["environment"]["verification"]["source_revision"], REVISION)
        startup = next(row for row in result["measurements"] if row["benchmark"] == "startup")
        frames = next(row for row in result["measurements"] if row["metric"] == "frameDurationCpuMs")
        self.assertEqual(startup["sample_count"], 10)
        self.assertEqual(frames["sample_count"], 30)

    def test_complete_macro_cli_rejects_swapped_variant_trace_identities(self):
        self.add_json()
        self.add_traces()
        self.output.mkdir()
        environment = self.write_environment()
        collect_results.collect(self.inputs, self.output, environment)
        manifest_path = self.output / "evidence-manifest.json"
        manifest = json.loads(manifest_path.read_text())
        for trace in manifest["traces"]:
            trace["variant"] = "reference" if trace["variant"] == "generated" else "generated"
        manifest_path.write_text(json.dumps(manifest))
        self.assertEqual(report.main([
            "--output", str(self.output), "--require-macro", "--evidence-manifest", str(manifest_path),
            str(self.output / "raw/001-benchmarkData.json"),
        ]), 2)

    def test_path_traversal_is_rejected(self):
        self.add_json()
        self.add_traces()
        manifest = collect_results.collect(self.inputs, self.output, self.environment)
        manifest["benchmark_json"][0]["path"] = "../outside.json"
        with self.assertRaisesRegex(report.ReportError, "inside"):
            report.verify_evidence(manifest, self.output, [])


if __name__ == "__main__":
    unittest.main()
