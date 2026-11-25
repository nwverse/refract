#!/usr/bin/env python3
"""Synthetic offline export tests; no Xcode, target or native timing is used."""

from __future__ import annotations

import copy
import hashlib
import io
import json
import os
import plistlib
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "common"))

from build_provenance import BUNDLE_NAMES, original_build_provenance
from export_iteration_manifest import (BINARY_PATH, MEMORY_PATH, METRICS_PATH, ExportError, export_manifest,
                                       main)
from paired_report import EvidenceError, make_report


class IterationManifestExportTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.root = self.base / "runs"
        self.derived_data = self.base / "DerivedData"
        self.revision = "a" * 40
        self.target = {"udid": "00000000-0000-0000-0000-000000000001", "name": "Synthetic simulator",
                       "model": "com.example.simulator", "os_version": "Synthetic OS", "architecture": "arm64"}
        self.toolchain = {"xcode": "Synthetic native toolchain"}
        self.environment = {"source_revision": self.revision, "target_label": "SIMULATOR", "device_result": False,
                            "target": self.target, "toolchain": self.toolchain,
                            "commands": ["xcresulttool get test-results metrics --path <result>"]}
        self.write_json(self.base / "environment.json", self.environment)
        self.write_original_products()
        self.build_hash = hashlib.sha256((self.derived_data / "refract-build-provenance.json").read_bytes()).hexdigest()
        for variant in ("generated", "reference"):
            for scenario in ("startup", "scroll", "stateUpdate"):
                for iteration in range(2, 31):
                    self.make_run(variant, scenario, iteration)
        self.output = self.base / "export"

    def write_json(self, path, payload):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")

    def write_original_products(self):
        products = self.derived_data / "Build/Products/Release-iphonesimulator"
        for bundle in BUNDLE_NAMES:
            path = products / bundle
            path.mkdir(parents=True)
            executable = Path(bundle).stem
            (path / executable).write_bytes(f"synthetic executable: {bundle}".encode())
            (path / executable).chmod(0o755)
            (path / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": executable}))
        (products / "RefractBenchUITests-Runner.app/Frameworks").mkdir()
        (products / "RefractBenchUITests-Runner.app/Frameworks/Support.dylib").write_bytes(b"support")
        source = self.derived_data / "Build/Products/RefractBench.xctestrun"
        source.write_bytes(plistlib.dumps({"RefractBenchUITests": {"TestingEnvironmentVariables": {
            "XCODE_SCHEME_NAME": "RefractBench"}}}))
        self.write_json(self.derived_data / "refract-build-provenance.json",
                        original_build_provenance(self.derived_data, self.revision))

    def run_path(self, variant, scenario, iteration):
        return self.root / f"{variant}-{scenario}-{iteration}"

    def startup_payload(self, variant, iteration, value=10.0):
        native = {"sourceRevision": self.revision, "variant": variant, "scenario": "startup", "iteration": iteration,
                  "metric": "XCTApplicationLaunchMetric", "unit": "ms", "durationMs": value}
        canonical = json.dumps(native, sort_keys=True, separators=(",", ":")).encode()
        return {**native, "nativeMeasurement": native,
                "nativeMeasurementSha256": hashlib.sha256(canonical).hexdigest()}

    def resource_payload(self, variant, scenario, iteration, metric, pid):
        return {"sourceRevision": self.revision, "variant": variant, "scenario": scenario, "iteration": iteration,
                "metric": metric, "bytes": 1024 if metric == "residentMemoryBytes" else 4096,
                "unit": "bytes", **({"pid": pid} if metric == "residentMemoryBytes" else {})}

    def make_run(self, variant, scenario, iteration):
        run = self.run_path(variant, scenario, iteration)
        raw = run / "raw"
        (raw / "exports").mkdir(parents=True)
        trace_name = f"{variant}-{scenario}-{iteration}.trace.zip"
        (raw / trace_name).write_bytes(f"synthetic profiler {variant} {scenario} {iteration}".encode())
        (raw / "results.xcresult.zip").write_bytes(b"synthetic xcresult archive")
        pid = 4000 + iteration + (1000 if variant == "reference" else 0)
        samples = None
        if scenario == "startup":
            self.write_json(raw / "exports/xctest-metrics.json", self.startup_payload(variant, iteration))
        else:
            samples = {"schema": 1, "session": 1, "sourceRevision": self.revision, "variant": variant,
                       "scenario": scenario, "iteration": iteration, "pid": pid, "completedIterations": 1,
                       "recordedIteration": iteration, "frameIntervalMs": [9.0, 10.0, 11.0],
                       "iterationByFrame": [iteration] * 3}
            self.write_json(raw / "native-samples.json", samples)
            self.write_json(raw / "exports/resident-memory.json",
                            self.resource_payload(variant, scenario, iteration, "residentMemoryBytes", pid))
        if scenario == "startup" and iteration == 2:
            self.write_json(raw / "exports/installed-binary.json",
                            self.resource_payload(variant, scenario, iteration, "installedBinaryBytes", pid))
        trace = {"schema": 1, "status": "complete", "session": 1, "source_revision": self.revision,
                 "variant": variant, "scenario": scenario, "iteration": iteration, "pid": pid,
                 "target_udid": self.target["udid"], "target_label": "SIMULATOR", "device_result": False,
                 "recorder": "xctrace", "template": "Synthetic template",
                 "native_iteration_completion": f"{variant} {scenario} complete 1",
                 "trace": f"raw/{trace_name}", "archived_package_name": trace_name.removesuffix(".zip"),
                 "bytes": (raw / trace_name).stat().st_size,
                 "sha256": hashlib.sha256((raw / trace_name).read_bytes()).hexdigest()}
        if samples is not None:
            trace["native_samples"] = {"path": "raw/native-samples.json",
                                       "sha256": hashlib.sha256((raw / "native-samples.json").read_bytes()).hexdigest()}
        self.write_json(raw / "iteration-trace.json", trace)
        (run / "refract-build-provenance.json").write_bytes(
            (self.derived_data / "refract-build-provenance.json").read_bytes())
        self.write_json(run / "iteration-trace-config.json", {
            "schema": 1, "source_revision": self.revision, "iteration": iteration,
            "control_directory": str(run.resolve() / "control"), "build_provenance_sha256": self.build_hash})
        files = {}
        for directory, _, names in os.walk(run):
            for name in sorted(names):
                path = Path(directory) / name
                files[path.relative_to(run).as_posix()] = {
                    "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        accepted = {"schema": 1, "status": "accepted-native-iteration", "source_revision": self.revision,
                    "variant": variant, "scenario": scenario, "iteration": iteration, "native_pid": pid,
                    "target_label": "SIMULATOR", "device_result": False, "target_udid": self.target["udid"],
                    "target_name": self.target["name"], "target_os_version": self.target["os_version"],
                    "xcode_version": self.toolchain["xcode"], "recorder_exit": 0,
                    "test_counts": {"passed": 1, "failed": 0, "skipped": 0},
                    "trace_zip": self.file_record(raw / trace_name),
                    "xcresult_zip": self.file_record(raw / "results.xcresult.zip"), "retained_files": files}
        if scenario == "startup":
            accepted["xctest_metrics_sha256"] = hashlib.sha256(
                (raw / "exports/xctest-metrics.json").read_bytes()).hexdigest()
        else:
            accepted["native_samples_sha256"] = trace["native_samples"]["sha256"]
        self.write_json(run / "accepted-evidence.json", accepted)
        files["accepted-evidence.json"] = {"bytes": (run / "accepted-evidence.json").stat().st_size,
                                           "sha256": hashlib.sha256((run / "accepted-evidence.json").read_bytes()).hexdigest()}
        self.write_json(run / "retained-file-hashes.json", {"schema": 1, "files": files})

    def file_record(self, path):
        return {"path": path.relative_to(path.parents[1]).as_posix(), "bytes": path.stat().st_size,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

    def replace_run_json(self, run, relative, payload):
        self.write_json(run / relative, payload)
        self.refresh_retained(run)

    def refresh_retained(self, run):
        accepted_path = run / "accepted-evidence.json"
        accepted = json.loads(accepted_path.read_text())
        for relative in list(accepted["retained_files"]):
            path = run / relative
            if not path.exists():
                del accepted["retained_files"][relative]
                continue
            accepted["retained_files"][relative] = {
                "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        self.write_json(accepted_path, accepted)
        files = copy.deepcopy(accepted["retained_files"])
        files["accepted-evidence.json"] = {
            "bytes": accepted_path.stat().st_size, "sha256": hashlib.sha256(accepted_path.read_bytes()).hexdigest()}
        self.write_json(run / "retained-file-hashes.json", {"schema": 1, "files": files})

    def export(self, output=None, selections=None):
        return export_manifest([self.root], self.derived_data, self.base / "environment.json",
                               output or self.output, selections)

    def test_exact_174_identities_and_raw_reductions_feed_complete_schema_2(self):
        manifest = self.export()
        self.assertEqual(manifest["schema"], 2)
        self.assertEqual(len(manifest["measurements"]), 174)
        self.assertEqual(len(manifest["resources"]), 118)
        identities = {(entry["variant"], entry["scenario"], entry["iteration"])
                      for entry in manifest["measurements"]}
        self.assertEqual(identities, {(variant, scenario, iteration)
                                      for variant in ("generated", "reference")
                                      for scenario in ("startup", "scroll", "stateUpdate")
                                      for iteration in range(2, 31)})
        self.assertFalse(any(entry["iteration"] == 1 for entry in manifest["measurements"]))
        frames = [entry for entry in manifest["measurements"] if entry["scenario"] != "startup"]
        self.assertTrue(all(entry["value"] == 11.0 and entry["aggregation"] == "p99" for entry in frames))
        report = make_report(manifest, self.output)
        self.assertEqual(report["status"], "pass")
        self.assertEqual(report["target_label"], "SIMULATOR")
        self.assertFalse(report["device_result"])
        self.assertFalse(report["physical_device_gate_satisfied"])
        second = self.base / "second-export"
        self.assertEqual(self.export(second), manifest)
        self.assertEqual((self.output / "manifest.json").read_bytes(), (second / "manifest.json").read_bytes())
        executable = self.output / ("products/DerivedData/Build/Products/Release-iphonesimulator/"
                                    "RefractBench.app/RefractBench")
        self.assertTrue(executable.stat().st_mode & 0o111)

    def test_missing_and_duplicate_pair_members_fail_before_manifest_creation(self):
        for scenario in ("startup", "scroll", "stateUpdate"):
            with self.subTest(scenario=scenario):
                partial = self.base / f"partial-{scenario}"
                shutil.copytree(self.root, partial)
                for run in partial.iterdir():
                    receipt = json.loads((run / "iteration-trace-config.json").read_text())
                    receipt["control_directory"] = str(run.resolve() / "control")
                    self.replace_run_json(run, "iteration-trace-config.json", receipt)
                shutil.rmtree(partial / f"generated-{scenario}-30")
                output = self.base / f"missing-{scenario}"
                with self.assertRaisesRegex(ExportError, "exactly 2...30"):
                    export_manifest([partial], self.derived_data, self.base / "environment.json", output)
                self.assertFalse(output.exists())
        duplicate = self.base / "duplicate"
        shutil.copytree(self.run_path("reference", "scroll", 30), duplicate / "reference-scroll-30")
        with self.assertRaisesRegex(ExportError, "Duplicate retained"):
            export_manifest([self.root, duplicate], self.derived_data, self.base / "environment.json", duplicate / "out")
        self.assertFalse((duplicate / "out").exists())

    def test_revision_build_and_target_cross_binding_are_rejected(self):
        run = self.run_path("generated", "scroll", 20)
        result = json.loads((run / "raw/iteration-trace.json").read_text())
        result["source_revision"] = "b" * 40
        self.replace_run_json(run, "raw/iteration-trace.json", result)
        with self.assertRaisesRegex(ExportError, "source_revision"):
            self.export()
        self.assertFalse(self.output.exists())

    def test_cross_build_is_rejected(self):
        run = self.run_path("reference", "startup", 2)
        (run / "refract-build-provenance.json").write_bytes(b"different retained build")
        self.refresh_retained(run)
        with self.assertRaisesRegex(ExportError, "checksum|different build"):
            self.export()
        self.assertFalse(self.output.exists())

    def test_target_mismatch_is_rejected(self):
        run = self.run_path("reference", "scroll", 20)
        accepted = json.loads((run / "accepted-evidence.json").read_text())
        accepted["target_os_version"] = "Another synthetic OS"
        self.replace_run_json(run, "accepted-evidence.json", accepted)
        with self.assertRaisesRegex(ExportError, "target"):
            self.export()
        self.assertFalse(self.output.exists())

    def test_incomplete_resource_set_creates_no_manifest_or_report(self):
        path = self.run_path("reference", "stateUpdate", 30) / MEMORY_PATH
        path.unlink()
        self.refresh_retained(self.run_path("reference", "stateUpdate", 30))
        with self.assertRaisesRegex(ExportError, "retained|Missing"):
            self.export()
        self.assertFalse(self.output.exists())
        self.assertFalse((self.base / "report").exists())

    def test_binary_pair_is_required(self):
        path = self.run_path("generated", "startup", 2) / BINARY_PATH
        path.unlink()
        self.refresh_retained(self.run_path("generated", "startup", 2))
        with self.assertRaisesRegex(ExportError, "installed binary"):
            self.export()
        self.assertFalse(self.output.exists())

    def test_startup_selector_binds_index_and_native_value_checksum(self):
        run = self.run_path("generated", "startup", 2)
        selected = self.startup_payload("generated", 2)
        selected["value"] = {"definition": "XCTApplicationLaunchMetric", "unit": "ms", "duration_ms": 12.5}
        canonical = json.dumps(selected, sort_keys=True, separators=(",", ":")).encode()
        selector = {"index": 0, "value_sha256": hashlib.sha256(canonical).hexdigest()}
        self.replace_run_json(run, METRICS_PATH, {"measurements": [selected]})
        accepted = json.loads((run / "accepted-evidence.json").read_text())
        accepted["xctest_metrics_sha256"] = hashlib.sha256((run / METRICS_PATH).read_bytes()).hexdigest()
        self.replace_run_json(run, "accepted-evidence.json", accepted)
        selections_path = self.base / "startup-selections.json"
        self.write_json(selections_path, {"schema": 1, "source_revision": self.revision,
                                          "build_provenance_sha256": self.build_hash,
                                          "selections": [{"variant": "generated", "scenario": "startup",
                                                          "iteration": 2, **selector}]})
        manifest = self.export(selections=selections_path)
        measurement = next(entry for entry in manifest["measurements"]
                           if (entry["variant"], entry["scenario"], entry["iteration"])
                           == ("generated", "startup", 2))
        self.assertEqual(measurement["value"], 12.5)
        self.assertEqual(measurement["metric_selector"], selector)
        report = make_report(manifest, self.output)
        sample = next(entry for entry in report["samples"] if entry["variant"] == "generated"
                      and entry["scenario"] == "startup" and entry["iteration"] == 2)
        self.assertEqual(sample["value"], 12.5)
        selected["value"]["duration_ms"] = 13.5
        self.replace_run_json(run, METRICS_PATH, {"measurements": [selected]})
        with self.assertRaisesRegex(ExportError, "checksum"):
            self.export(self.base / "tampered-selector")

    def test_missing_selector_and_first_display_substitution_fail(self):
        run = self.run_path("generated", "startup", 2)
        native = self.startup_payload("generated", 2)
        native["value"] = {"definition": "XCTApplicationLaunchMetric", "unit": "ms", "duration_ms": 10.0}
        self.replace_run_json(run, METRICS_PATH, {"measurements": [native]})
        accepted = json.loads((run / "accepted-evidence.json").read_text())
        accepted["xctest_metrics_sha256"] = hashlib.sha256((run / METRICS_PATH).read_bytes()).hexdigest()
        self.replace_run_json(run, "accepted-evidence.json", accepted)
        with self.assertRaisesRegex(EvidenceError, "selection|index"):
            self.export()
        self.assertFalse(self.output.exists())
        self.replace_run_json(run, METRICS_PATH, {"sourceRevision": self.revision, "variant": "generated",
                                                  "scenario": "startup", "iteration": 2,
                                                  "firstDisplay": {"clock": "CACurrentMediaTime",
                                                                   "timestamp": "12345.25"}})
        accepted["xctest_metrics_sha256"] = hashlib.sha256((run / METRICS_PATH).read_bytes()).hexdigest()
        self.replace_run_json(run, "accepted-evidence.json", accepted)
        with self.assertRaisesRegex(ExportError, "firstDisplay timestamp is not"):
            self.export()
        self.assertFalse(self.output.exists())

    def test_corrupt_raw_array_cannot_be_relabelled_with_the_old_p99(self):
        run = self.run_path("generated", "scroll", 2)
        samples_path = run / "raw/native-samples.json"
        samples = json.loads(samples_path.read_text())
        samples["frameIntervalMs"] = [9.0, 10.0, 100.0]
        samples["iterationByFrame"] = [2, 2, 2]
        self.replace_run_json(run, "raw/native-samples.json", samples)
        accepted_path = run / "accepted-evidence.json"
        accepted = json.loads(accepted_path.read_text())
        accepted["native_samples_sha256"] = hashlib.sha256(samples_path.read_bytes()).hexdigest()
        self.replace_run_json(run, "accepted-evidence.json", accepted)
        result = json.loads((run / "raw/iteration-trace.json").read_text())
        result["native_samples"]["sha256"] = accepted["native_samples_sha256"]
        self.replace_run_json(run, "raw/iteration-trace.json", result)
        manifest = self.export()
        measurement = next(entry for entry in manifest["measurements"]
                           if (entry["variant"], entry["scenario"], entry["iteration"])
                           == ("generated", "scroll", 2))
        self.assertEqual(measurement["value"], 100.0)
        report = make_report(manifest, self.output)
        sample = next(entry for entry in report["samples"] if entry["variant"] == "generated"
                      and entry["scenario"] == "scroll" and entry["iteration"] == 2)
        self.assertEqual(sample["source_samples"], [9.0, 10.0, 100.0])
        self.assertEqual(sample["value"], 100.0)

    def test_changed_profiler_bytes_cannot_reuse_the_accepted_checksum(self):
        run = self.run_path("generated", "scroll", 2)
        archive = run / "raw/generated-scroll-2.trace.zip"
        archive.write_bytes(b"changed synthetic profiler")
        self.refresh_retained(run)
        with self.assertRaisesRegex(ExportError, "trace_zip|checksum"):
            self.export()
        self.assertFalse(self.output.exists())

    def test_existing_output_is_not_replaced(self):
        self.output.mkdir()
        marker = self.output / "manifest.json"
        marker.write_bytes(b"existing")
        with self.assertRaisesRegex(ExportError, "Refusing to replace"):
            self.export()
        self.assertEqual(marker.read_bytes(), b"existing")
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            self.assertEqual(main(["--run-root", str(self.root), "--derived-data", str(self.derived_data),
                                   "--environment", str(self.base / "environment.json"),
                                   "--output", str(self.output)]), 2)
        self.assertIn("no complete manifest was written", stderr.getvalue())

    def test_deterministic_cli_prints_only_export_counts(self):
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            self.assertEqual(main(["--run-root", str(self.root), "--derived-data", str(self.derived_data),
                                   "--environment", str(self.base / "environment.json"),
                                   "--output", str(self.output)]), 0)
        self.assertIn("measurements=174", stdout.getvalue())
        self.assertIn("resources=118", stdout.getvalue())
        self.assertTrue((self.output / "manifest.json").is_file())


if __name__ == "__main__":
    unittest.main()
