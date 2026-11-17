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

    def add_json(self, name="benchmarkData.json", benchmarks=None):
        path = self.inputs / name
        if benchmarks is None:
            benchmarks = []
            for variant in ("generated", "reference"):
                for scenario in ("startup", "scroll", "stateUpdate"):
                    benchmarks.append({
                        "name": f"dev.refract.bench.test.SettingsMacrobenchmark.{variant}{scenario}",
                        "className": "dev.refract.bench.test.SettingsMacrobenchmark",
                        "profilerOutputs": [{
                            "type": "PerfettoTrace", "label": "Trace Iteration 0",
                            "filename": collect_results.trace_filename(variant, scenario),
                        }],
                    })
        path.write_text(json.dumps(benchmarks))
        return path

    def add_traces(self):
        for variant in ("generated", "reference"):
            for scenario in ("startup", "scroll", "stateUpdate"):
                filename = collect_results.trace_filename(variant, scenario)
                (self.inputs / filename).write_bytes(b"trace")

    def test_copies_json_and_all_six_perfetto_scenarios(self):
        self.add_json()
        self.add_traces()
        manifest = collect_results.collect(self.inputs, self.output)
        self.assertEqual(len(manifest["benchmark_json"]), 1)
        self.assertEqual(len(manifest["traces"]), 6)
        self.assertTrue(all(item["variant"] and item["scenario"] for item in manifest["traces"]))
        self.assertTrue(all(item["androidx_benchmark"] for item in manifest["traces"]))
        self.assertEqual(collect_results.trace_identity("Class_generatedMacrobenchmark[scroll]"), ("generated", "scroll"))
        for item in manifest["traces"]:
            self.assertEqual((self.output / item["path"]).read_bytes(), b"trace")
        verified = report.verify_evidence(manifest, self.output, [self.output / "raw/001-benchmarkData.json"])
        self.assertEqual(len(verified["traces"]), 6)

    def test_json_is_required(self):
        with self.assertRaisesRegex(collect_results.EvidenceError, "No AndroidX"):
            collect_results.collect(self.inputs, self.output)

    def test_missing_or_unreferenced_trace_is_rejected(self):
        payload = json.loads(self.add_json().read_text())
        payload[0]["profilerOutputs"][0]["filename"] = "missing.perfetto-trace"
        source = self.inputs / "benchmarkData.json"
        source.write_text(json.dumps(payload))
        self.add_traces()
        with self.assertRaisesRegex(collect_results.EvidenceError, "missing or ambiguous"):
            collect_results.collect(self.inputs, self.output)

    def test_macro_without_profiler_outputs_cannot_pass(self):
        payload = json.loads(self.add_json().read_text())
        payload[0]["profilerOutputs"] = []
        source = self.inputs / "benchmarkData.json"
        source.write_text(json.dumps(payload))
        self.add_traces()
        with self.assertRaisesRegex(collect_results.EvidenceError, "no profilerOutputs"):
            collect_results.collect(self.inputs, self.output)

    def test_checksum_mismatch_and_wrong_input_are_rejected(self):
        source = self.add_json()
        self.add_traces()
        manifest = collect_results.collect(self.inputs, self.output)
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
        manifest = collect_results.collect(self.inputs, self.output)
        trace = self.output / manifest["traces"][0]["path"]
        trace.write_bytes(b"")
        self.assertEqual(manifest["traces"][0]["bytes"], 5)
        with self.assertRaisesRegex(report.ReportError, "checksum mismatch"):
            report.verify_evidence(manifest, self.output,
                                   [self.output / "raw/001-benchmarkData.json"])

    def test_complete_macro_cli_verifies_preserved_evidence(self):
        values = []
        for variant in ("Generated", "Reference"):
            for scenario, metrics in (
                ("startup", {"startupMs": {"runs": [1.0] * 10}}),
                ("scroll", {"frameDurationCpuMs": {"runs": [1.0]}, "memoryRssAnonKb": {"runs": [100.0]}}),
                ("stateUpdate", {"frameDurationCpuMs": {"runs": [1.0]}, "memoryRssAnonKb": {"runs": [100.0]}}),
            ):
                value = report_test.benchmark(variant, scenario, metrics)
                value["repeatIterations"] = 10
                value["profilerOutputs"] = [{
                    "type": "PerfettoTrace",
                    "filename": collect_results.trace_filename(variant.lower(), scenario),
                }]
                values.append(value)
        source = self.add_json()
        source.write_text(json.dumps(values))
        self.add_traces()
        collect_results.collect(self.inputs, self.output)
        environment = self.output / "environment.json"
        environment.write_text(json.dumps({"emulator": True, "source_revision": REVISION}))
        arguments = ["--output", str(self.output), "--environment", str(environment),
                     "--require-macro", "--evidence-manifest", str(self.output / "evidence-manifest.json"),
                     str(self.output / "raw/001-benchmarkData.json")]
        self.assertEqual(report.main(arguments), 0)
        result = json.loads((self.output / "report.json").read_text())
        self.assertTrue(result["macro_evidence_required"])
        self.assertEqual(result["environment"]["verification"]["source_revision"], REVISION)

    def test_path_traversal_is_rejected(self):
        self.add_json()
        self.add_traces()
        manifest = collect_results.collect(self.inputs, self.output)
        manifest["benchmark_json"][0]["path"] = "../outside.json"
        with self.assertRaisesRegex(report.ReportError, "inside"):
            report.verify_evidence(manifest, self.output, [])


if __name__ == "__main__":
    unittest.main()
