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
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "common"))

from build_provenance import BUNDLE_NAMES, original_build_provenance
from export_iteration_manifest import (BINARY_PATH, LEGACY_METRICS_PATH, MEMORY_PATH, METRICS_PATH, TESTS_PATH,
                                       ExportError, export_manifest, main)
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

    def write_producer_packet(self, path, payload):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, allow_nan=False), encoding="utf-8")

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

    def xctest_device(self):
        return {"architecture": self.target["architecture"], "deviceId": self.target["udid"],
                "deviceName": self.target["name"], "modelName": self.target["model"],
                "osBuildNumber": "SYNTHETIC1", "osVersion": self.target["os_version"],
                "platform": "iOS Simulator"}

    def startup_payload(self, variant, iteration, value=10.0, pid=None):
        identifier = f"RefractBenchUITests/test{variant.capitalize()}StartupTrace()"
        native = {"sourceRevision": self.revision, "variant": variant, "scenario": "startup", "iteration": iteration,
                  "pid": 4000 + iteration + (1000 if variant == "reference" else 0) if pid is None else pid,
                  "metric": "XCTApplicationLaunchMetric",
                  "nativeMetricIdentifier": "com.apple.dt.XCTMetric_ApplicationLaunch-AppLaunch.duration",
                  "nativeTestIdentifier": identifier,
                  "nativeValue": {"unitOfMeasurement": "s", "measurements": [value / 1000]},
                  "value": {"definition": "XCTApplicationLaunchMetric", "unit": "ms", "duration_ms": value}}
        canonical = json.dumps(native, sort_keys=True, separators=(",", ":")).encode()
        return {"measurements": [native], "metric_selector": {
            "index": 0, "value_sha256": hashlib.sha256(canonical).hexdigest()}}

    def resource_payload(self, variant, scenario, iteration, metric, pid):
        return {"sourceRevision": self.revision, "variant": variant, "scenario": scenario, "iteration": iteration,
                "metric": metric, "bytes": 1024 if metric == "residentMemoryBytes" else 4096,
                "unit": "bytes", **({"pid": pid} if metric == "residentMemoryBytes" else {})}

    def write_producer_native_inputs(self, run, variant, scenario, iteration, pid):
        raw = run / "raw"
        packets = {}
        for role, relative, state in (("native_process", "control/native-process.json", "ready"),
                                      ("request", "raw/request.json", "ready"),
                                      ("native_completion", "control/native-completion.json", "complete"),
                                      ("completion", "raw/completion.json", "complete")):
            packet = {"schema": 1, "session": 1, "revision": self.revision, "variant": variant,
                      "scenario": scenario, "iteration": iteration, "pid": pid, "process": "running", "state": state}
            if state == "complete":
                packet["completion"] = f"{variant} {scenario} complete 1"
            self.write_producer_packet(run / relative, packet)
            packets[role] = {"path": relative, "sha256": self.file_record(run / relative)["sha256"]}
        memory = self.resource_payload(variant, scenario, iteration, "residentMemoryBytes", pid)
        binary = self.resource_payload(variant, scenario, iteration, "installedBinaryBytes", pid)
        self.write_json(raw / "native-resources.json", [
            {**memory, "schema": 1, "session": 1, "definition": "task_info.TASK_VM_INFO.resident_size"},
            {**binary, "schema": 1, "session": 1, "definition": "Bundle.main.regular-file-bytes",
             "bundle": "RefractBench.app", "files": [{"path": "RefractBench", "bytes": binary["bytes"],
                                                     "sha256": "0" * 64}]},
        ])
        exports = {}
        for metric, filename, payload, definition in (
                ("residentMemoryBytes", "native-memory.json", memory, "task_info.TASK_VM_INFO.resident_size"),
                ("installedBinaryBytes", "native-binary.json", binary, "Bundle.main.regular-file-bytes")):
            self.write_json(raw / filename, payload)
            alias = None
            if metric == "residentMemoryBytes" and scenario != "startup":
                alias = MEMORY_PATH
            elif metric == "installedBinaryBytes" and scenario == "startup" and iteration == 2:
                alias = BINARY_PATH
            if alias is not None:
                self.write_json(run / alias, payload)
            selected = run / (alias or f"raw/{filename}")
            self.assertEqual(selected.read_bytes(), (raw / filename).read_bytes())
            exports[metric] = {"path": alias or f"raw/{filename}",
                               "sha256": hashlib.sha256(selected.read_bytes()).hexdigest(), "definition": definition}
        return {"path": "raw/native-resources.json",
                "sha256": self.file_record(raw / "native-resources.json")["sha256"], "exports": exports}, packets

    def make_run(self, variant, scenario, iteration):
        run = self.run_path(variant, scenario, iteration)
        control = run / "control"
        raw = run / "raw"
        (raw / "exports").mkdir(parents=True)
        control.mkdir()
        source = self.derived_data / "Build/Products/RefractBench.xctestrun"
        configuration_name = "iteration-trace-config-" + hashlib.sha256(
            f"{self.revision}\0{control}\0{iteration}".encode()).hexdigest()[:24] + ".xctestrun"
        configuration = {"__xctestrun_metadata__": {"ContainerInfo": {
            "ContainerName": "RefractBench", "SchemeName": "RefractBench"}, "FormatVersion": 1},
                         "RefractBenchUITests": {"TestingEnvironmentVariables": {
            "XCODE_SCHEME_NAME": "RefractBench", "REFRACT_BENCH_REVISION": self.revision,
            "REFRACT_BENCH_TRACE_CONTROL": str(control), "REFRACT_BENCH_TRACE_ITERATION": str(iteration)}}}
        archived_configuration = plistlib.dumps(configuration)
        (run / "iteration-trace-config.xctestrun").write_bytes(archived_configuration)
        (source.parent / configuration_name).write_bytes(archived_configuration)
        self.write_json(run / "iteration-trace-config.json", {
            "schema": 1, "source_revision": self.revision, "iteration": iteration,
            "control_directory": str(control), "build_provenance_sha256": self.build_hash,
            "path": configuration_name, "archive": "iteration-trace-config.xctestrun",
            "source_xctestrun": source.name,
            "configuration_sha256": hashlib.sha256(archived_configuration).hexdigest()})
        self.write_target_evidence(run)
        trace_name = f"{variant}-{scenario}-{iteration}.trace.zip"
        (raw / trace_name).write_bytes(f"synthetic profiler {variant} {scenario} {iteration}".encode())
        (raw / "results.xcresult.zip").write_bytes(b"synthetic xcresult archive")
        pid = 4000 + iteration + (1000 if variant == "reference" else 0)
        native_resources, native_packets = self.write_producer_native_inputs(run, variant, scenario, iteration, pid)
        samples = None
        startup_selector = None
        if scenario == "startup":
            normalized = self.startup_payload(variant, iteration, pid=pid)
            selector = normalized["metric_selector"]
            native = normalized["measurements"][0]
            identifier = native["nativeTestIdentifier"]
            test_configuration = {"configurationId": "1", "configurationName": "Test Scheme Action"}
            raw_metrics = [{"testIdentifier": identifier, "testRuns": [{
                "device": self.xctest_device(), "testPlanConfiguration": test_configuration,
                "metrics": [{"identifier": native["nativeMetricIdentifier"], **native["nativeValue"]}],
            }]}]
            raw_tests = {"testPlanConfigurations": [test_configuration],
                         "testNodes": [{"nodeType": "Test Case", "nodeIdentifier": identifier, "name": identifier,
                                        "result": "Passed", "durationInSeconds": 1.0}]}
            self.write_json(raw / "exports/xctest-metrics.json", raw_metrics)
            self.write_json(raw / "exports/xctest-tests.json", raw_tests)
            normalized["provenance"] = {
                "native_test_identifier_url": "test://com.apple.xcode/RefractBench/RefractBenchUITests/" + identifier[:-2],
                "trace_receipt_sha256": "", "trace_configuration_receipt_sha256": "",
                "native_pid": pid, "native_process_packets": native_packets,
                "export_commands": [
                    ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", "results.xcresult",
                     "--format", "json"],
                    ["xcrun", "xcresulttool", "get", "test-results", "metrics", "--path", "results.xcresult",
                     "--format", "json", "--test-id", identifier],
                ],
                "raw_exports": {name: {"path": f"raw/exports/{name}",
                                       "sha256": self.file_record(raw / "exports" / name)["sha256"]}
                                for name in ("xctest-tests.json", "xctest-metrics.json")},
            }
            self.write_json(run / METRICS_PATH, normalized)
            startup_selector = {"path": METRICS_PATH, "sha256": self.file_record(run / METRICS_PATH)["sha256"],
                                "duration_ms": native["value"]["duration_ms"], "metric_selector": selector}
        else:
            samples = {"schema": 1, "session": 1, "sourceRevision": self.revision, "variant": variant,
                       "scenario": scenario, "iteration": iteration, "pid": pid, "completedIterations": 1,
                       "recordedIteration": iteration, "frameIntervalMs": [9.0, 10.0, 11.0],
                       "iterationByFrame": [iteration] * 3}
        if scenario != "startup":
            self.write_json(raw / "native-samples.json", samples)
        trace = {"schema": 1, "status": "complete", "session": 1, "source_revision": self.revision,
                 "variant": variant, "scenario": scenario, "iteration": iteration, "pid": pid,
                 "target_udid": self.target["udid"], "target_label": "SIMULATOR", "device_result": False,
                 "recorder": "xctrace", "template": "Synthetic template",
                 "native_iteration_completion": f"{variant} {scenario} complete 1",
                 "trace": f"raw/{trace_name}", "archived_package_name": trace_name.removesuffix(".zip"),
                 "bytes": (raw / trace_name).stat().st_size, "native_resources": native_resources,
                 "sha256": hashlib.sha256((raw / trace_name).read_bytes()).hexdigest()}
        if startup_selector is not None:
            trace["native_launch_metric"] = startup_selector
        if samples is not None:
            trace["native_samples"] = {"path": "raw/native-samples.json",
                                       "sha256": hashlib.sha256((raw / "native-samples.json").read_bytes()).hexdigest()}
        normalized_path = run / METRICS_PATH
        self.write_producer_packet(raw / "iteration-trace.json", trace)
        if normalized_path.exists():
            normalized = json.loads(normalized_path.read_text())
            persisted_trace = dict(trace)
            persisted_trace.pop("native_launch_metric", None)
            normalized["provenance"].update(
                trace_receipt_sha256=self.file_record(raw / "iteration-trace.json")["sha256"],
                trace_configuration_receipt_sha256=self.file_record(run / "iteration-trace-config.json")["sha256"])
            self.write_json(normalized_path, normalized)
        (run / "refract-build-provenance.json").write_bytes(
            (self.derived_data / "refract-build-provenance.json").read_bytes())
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
                    "xctest_summary_sha256": hashlib.sha256(
                        (raw / "exports/xctest-summary.json").read_bytes()).hexdigest(),
                    "xctest_tests_sha256": hashlib.sha256(
                        (raw / "exports/xctest-tests.json").read_bytes()).hexdigest(),
                    "trace_zip": self.file_record(raw / trace_name),
                    "xcresult_zip": self.file_record(raw / "results.xcresult.zip"), "retained_files": files}
        if scenario == "startup":
            accepted["xctest_metrics_sha256"] = hashlib.sha256(
                (run / LEGACY_METRICS_PATH).read_bytes()).hexdigest()
            accepted["normalized_metrics_sha256"] = hashlib.sha256(
                (run / METRICS_PATH).read_bytes()).hexdigest()
        else:
            accepted["native_samples_sha256"] = trace["native_samples"]["sha256"]
        self.write_json(run / "accepted-evidence.json", accepted)
        files["accepted-evidence.json"] = {"bytes": (run / "accepted-evidence.json").stat().st_size,
                                           "sha256": hashlib.sha256((run / "accepted-evidence.json").read_bytes()).hexdigest()}
        self.write_json(run / "retained-file-hashes.json", {"schema": 1, "files": files})

    def file_record(self, path):
        return {"path": path.relative_to(path.parents[1]).as_posix(), "bytes": path.stat().st_size,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

    def write_target_evidence(self, run):
        device = {"architecture": self.target["architecture"], "deviceId": self.target["udid"],
                  "deviceName": self.target["name"], "modelName": self.target["model"],
                  "osBuildNumber": "SYNTHETIC1", "osVersion": self.target["os_version"],
                  "platform": "iOS Simulator"}
        self.write_json(run / "raw/exports/xctest-summary.json", {
            "devicesAndConfigurations": [{"device": device, "expectedFailures": 0, "failedTests": 0,
                                          "passedTests": 1, "skippedTests": 0}],
            "result": "Passed", "passedTests": 1, "failedTests": 0, "skippedTests": 0})
        self.write_json(run / "raw/exports/xctest-tests.json", {
            "devices": [device], "testNodes": [{"nodeType": "Test Plan", "result": "Passed"}],
            "testPlanConfigurations": [{"configurationId": "1", "configurationName": "Test Scheme Action"}]})
        self.write_json(run / "target.json", {"target_label": "SIMULATOR", "device_result": False,
                                              "model": self.target["model"], "state": "Booted",
                                              "udid": self.target["udid"]})
        self.write_json(run / "simulators.json", {"devices": {"synthetic-runtime": [{
            "udid": self.target["udid"], "name": self.target["name"], "state": "Booted",
            "deviceTypeIdentifier": self.target["model"], "isAvailable": True}]}})
        self.write_json(run / "targets.json", {"devices": [{
            "identifier": self.target["udid"],
            "deviceProperties": {"bootState": "booted", "name": self.target["name"],
                                 "osVersionNumber": self.target["os_version"]},
            "hardwareProperties": {"udid": self.target["udid"], "reality": "simulated",
                                   "marketingName": self.target["model"],
                                   "cpuType": {"name": self.target["architecture"]}}}]})

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
        for run in self.root.iterdir():
            trace = json.loads((run / "raw/iteration-trace.json").read_text())
            scenario, iteration = trace["scenario"], trace["iteration"]
            self.assertEqual((run / MEMORY_PATH).exists(), scenario != "startup")
            self.assertEqual((run / BINARY_PATH).exists(), scenario == "startup" and iteration == 2)
            self.assertNotIn("native_launch_metric", trace,
                             "the on-disk producer receipt precedes its stdout-only launch result")
            if scenario == "startup":
                metrics = json.loads((run / METRICS_PATH).read_text())
                self.assertEqual(metrics["provenance"]["trace_receipt_sha256"],
                                 self.file_record(run / "raw/iteration-trace.json")["sha256"])
            for metric, alias in (("residentMemoryBytes", MEMORY_PATH), ("installedBinaryBytes", BINARY_PATH)):
                original = run / ("raw/native-memory.json" if metric == "residentMemoryBytes"
                                  else "raw/native-binary.json")
                selected = run / trace["native_resources"]["exports"][metric]["path"]
                self.assertEqual(selected.read_bytes(), original.read_bytes())
                self.assertEqual(self.file_record(selected)["sha256"],
                                 trace["native_resources"]["exports"][metric]["sha256"])
                if (scenario == "startup" and metric == "residentMemoryBytes") \
                        or (metric == "installedBinaryBytes" and (scenario != "startup" or iteration != 2)):
                    self.assertFalse((run / alias).exists())
        with mock.patch("export_iteration_manifest.checked_frame_samples",
                        wraps=__import__("paired_report").checked_frame_samples) as checked_frames:
            self.export(self.base / "platform-checked")
            self.assertTrue(all(call.kwargs.get("platform") == "ios"
                                for call in checked_frames.call_args_list))

    def rebind_run(self, run):
        control = str(run.resolve() / "control")
        receipt_path = run / "iteration-trace-config.json"
        receipt = json.loads(receipt_path.read_text())
        plist_path = run / "iteration-trace-config.xctestrun"
        configuration = plistlib.loads(plist_path.read_bytes())
        configuration["RefractBenchUITests"]["TestingEnvironmentVariables"]["REFRACT_BENCH_TRACE_CONTROL"] = control
        content = plistlib.dumps(configuration)
        plist_path.write_bytes(content)
        identity = hashlib.sha256(f"{self.revision}\0{control}\0{receipt['iteration']}".encode()).hexdigest()[:24]
        name = f"iteration-trace-config-{identity}.xctestrun"
        (self.derived_data / "Build/Products" / name).write_bytes(content)
        receipt.update(path=name, control_directory=control,
                       configuration_sha256=hashlib.sha256(content).hexdigest())
        self.replace_run_json(run, "iteration-trace-config.json", receipt)
        normalized_path = run / METRICS_PATH
        if normalized_path.is_file():
            normalized = json.loads(normalized_path.read_text())
            normalized["provenance"]["trace_configuration_receipt_sha256"] = self.file_record(receipt_path)["sha256"]
            self.replace_run_json(run, METRICS_PATH, normalized)

    def test_missing_and_duplicate_pair_members_fail_before_manifest_creation(self):
        for scenario in ("startup", "scroll", "stateUpdate"):
            with self.subTest(scenario=scenario):
                partial = self.base / f"partial-{scenario}"
                shutil.copytree(self.root, partial)
                for scenario_run in partial.iterdir():
                    self.rebind_run(scenario_run)
                shutil.rmtree(partial / f"generated-{scenario}-30")
                output = self.base / f"missing-{scenario}"
                with self.assertRaisesRegex(ExportError, "exactly 2...30"):
                    export_manifest([partial], self.derived_data, self.base / "environment.json", output)
                self.assertFalse(output.exists())
        duplicate = self.base / "duplicate"
        shutil.copytree(self.run_path("reference", "scroll", 30), duplicate / "reference-scroll-30")
        self.rebind_run(duplicate / "reference-scroll-30")
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

    def test_normalized_selector_is_embedded_and_external_override_is_rejected(self):
        run = self.run_path("generated", "startup", 2)
        original = json.loads((run / METRICS_PATH).read_text())
        manifest = self.export()
        measurement = next(entry for entry in manifest["measurements"]
                           if (entry["variant"], entry["scenario"], entry["iteration"])
                           == ("generated", "startup", 2))
        self.assertEqual(measurement["value"], 10.0)
        self.assertEqual(measurement["metric_selector"], original["metric_selector"])
        selected = copy.deepcopy(original)
        selected["measurements"][0]["value"]["duration_ms"] = 12.5
        canonical = json.dumps(selected["measurements"][0], sort_keys=True, separators=(",", ":")).encode()
        external_selector = {"index": 0, "value_sha256": hashlib.sha256(canonical).hexdigest()}
        selections_path = self.base / "startup-selections.json"
        self.write_json(selections_path, {"schema": 1, "source_revision": self.revision,
                                          "build_provenance_sha256": self.build_hash,
                                          "selections": [{"variant": "generated", "scenario": "startup",
                                                          "iteration": 2, **external_selector}]})
        with self.assertRaisesRegex(ExportError, "external startup selector"):
            self.export(self.base / "external-selector", selections=selections_path)
        self.assertFalse((self.base / "external-selector").exists())
        selected["measurements"][0]["nativeValue"]["measurements"] = [0.0125]
        canonical = json.dumps(selected["measurements"][0], sort_keys=True, separators=(",", ":")).encode()
        external_selector = {"index": 0, "value_sha256": hashlib.sha256(canonical).hexdigest()}
        raw_metrics = json.loads((run / LEGACY_METRICS_PATH).read_text())
        raw_metrics[0]["testRuns"][0]["metrics"][0]["measurements"] = [0.0125]
        selected["metric_selector"] = external_selector
        selected["provenance"]["raw_exports"]["xctest-metrics.json"]["sha256"] = hashlib.sha256(
            (json.dumps(raw_metrics, indent=2, sort_keys=True) + "\n").encode()).hexdigest()
        self.replace_run_json(run, METRICS_PATH, selected)
        self.replace_run_json(run, LEGACY_METRICS_PATH, raw_metrics)
        measurement = next(entry for entry in self.export(self.base / "updated-native-sample")["measurements"]
                           if (entry["variant"], entry["scenario"], entry["iteration"])
                           == ("generated", "startup", 2))
        self.assertEqual(measurement["value"], 12.5)
        selected["measurements"][0]["value"]["duration_ms"] = 13.5
        self.replace_run_json(run, METRICS_PATH, selected)
        with self.assertRaisesRegex(EvidenceError, "checksum"):
            self.export(self.base / "tampered-selector")

    def test_missing_selector_and_first_display_substitution_fail(self):
        run = self.run_path("generated", "startup", 2)
        native = self.startup_payload("generated", 2)
        native.pop("metric_selector")
        self.replace_run_json(run, METRICS_PATH, native)
        accepted = json.loads((run / "accepted-evidence.json").read_text())
        accepted["normalized_metrics_sha256"] = hashlib.sha256((run / METRICS_PATH).read_bytes()).hexdigest()
        self.replace_run_json(run, "accepted-evidence.json", accepted)
        with self.assertRaisesRegex(KeyError, "provenance"):
            self.export()
        self.assertFalse(self.output.exists())
        normalized_path = run / METRICS_PATH
        normalized_path.unlink()
        self.refresh_retained(run)
        self.replace_run_json(run, LEGACY_METRICS_PATH, {"sourceRevision": self.revision, "variant": "generated",
                                                         "scenario": "startup", "iteration": 2,
                                                         "firstDisplay": {"clock": "CACurrentMediaTime",
                                                                          "timestamp": "12345.25"}})
        accepted["xctest_metrics_sha256"] = hashlib.sha256((run / LEGACY_METRICS_PATH).read_bytes()).hexdigest()
        self.replace_run_json(run, "accepted-evidence.json", accepted)
        self.replace_run_json(run, TESTS_PATH, {"devices": [self.xctest_device()]})
        accepted = json.loads((run / "accepted-evidence.json").read_text())
        accepted["xctest_tests_sha256"] = self.file_record(run / TESTS_PATH)["sha256"]
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

    def test_configuration_identity_archive_and_hosted_environment_are_bound(self):
        run = self.run_path("generated", "scroll", 2)
        receipt = json.loads((run / "iteration-trace-config.json").read_text())
        receipt.update(configuration_sha256="0" * 64, path="not-a-real-config.xctestrun",
                       source_xctestrun="not-the-source.xctestrun")
        self.replace_run_json(run, "iteration-trace-config.json", receipt)
        with self.assertRaisesRegex(ExportError, "source_xctestrun|configuration name"):
            self.export()
        self.assertFalse(self.output.exists())

    def test_swapped_internally_consistent_configurations_are_rejected(self):
        first = self.run_path("generated", "scroll", 2)
        second = self.run_path("reference", "scroll", 2)
        receipts = [json.loads((run / "iteration-trace-config.json").read_text()) for run in (first, second)]
        contents = [(run / "iteration-trace-config.xctestrun").read_bytes() for run in (first, second)]
        for run, receipt, content in zip((first, second), receipts, reversed(contents)):
            (run / "iteration-trace-config.xctestrun").write_bytes(content)
            receipt["configuration_sha256"] = hashlib.sha256(content).hexdigest()
            (self.derived_data / "Build/Products" / receipt["path"]).write_bytes(content)
            self.replace_run_json(run, "iteration-trace-config.json", receipt)
        with self.assertRaisesRegex(ExportError, "REFRACT_BENCH_TRACE_CONTROL"):
            self.export()
        self.assertFalse(self.output.exists())

    def test_raw_native_session_must_match_the_iteration_receipt(self):
        run = self.run_path("generated", "scroll", 2)
        path = run / "raw/native-samples.json"
        samples = json.loads(path.read_text())
        samples["session"] = 2
        self.replace_run_json(run, "raw/native-samples.json", samples)
        checksum = hashlib.sha256(path.read_bytes()).hexdigest()
        accepted = json.loads((run / "accepted-evidence.json").read_text())
        accepted["native_samples_sha256"] = checksum
        self.replace_run_json(run, "accepted-evidence.json", accepted)
        result = json.loads((run / "raw/iteration-trace.json").read_text())
        result["native_samples"]["sha256"] = checksum
        self.replace_run_json(run, "raw/iteration-trace.json", result)
        with self.assertRaisesRegex(ExportError, "Native sample session"):
            self.export()
        self.assertFalse(self.output.exists())

    def test_target_metadata_is_bound_to_real_shaped_exports_and_probes(self):
        for key, replacement in (("model", "unrelated-model"), ("architecture", "unrelated-architecture"),
                                 ("udid", "00000000-0000-0000-0000-000000000099")):
            with self.subTest(key=key):
                environment = copy.deepcopy(self.environment)
                environment["target"][key] = replacement
                self.write_json(self.base / "environment.json", environment)
                output = self.base / f"target-{key}"
                with self.assertRaisesRegex(ExportError, "target|Target|device|XCTest"):
                    self.export(output)
                self.assertFalse(output.exists())
        run = self.run_path("generated", "scroll", 2)
        self.write_json(self.base / "environment.json", self.environment)
        summary_path = run / "raw/exports/xctest-summary.json"
        summary = json.loads(summary_path.read_text())
        summary["devicesAndConfigurations"][0]["device"]["architecture"] = "unrelated-architecture"
        self.replace_run_json(run, "raw/exports/xctest-summary.json", summary)
        accepted = json.loads((run / "accepted-evidence.json").read_text())
        accepted["xctest_summary_sha256"] = hashlib.sha256(summary_path.read_bytes()).hexdigest()
        self.replace_run_json(run, "accepted-evidence.json", accepted)
        with self.assertRaisesRegex(ExportError, "device records"):
            self.export(self.base / "forged-summary")
        self.assertFalse((self.base / "forged-summary").exists())

    def test_toolchain_is_bounded_and_commands_are_explicitly_external_assertions(self):
        environment = copy.deepcopy(self.environment)
        environment["toolchain"] = {"xcode": self.toolchain["xcode"], "invented": "not retained evidence"}
        environment["commands"] = ["not an acquisition or export command"]
        self.write_json(self.base / "environment.json", environment)
        with self.assertRaisesRegex(ExportError, "Toolchain"):
            self.export()
        self.assertFalse(self.output.exists())
        environment["toolchain"] = {"xcode": self.toolchain["xcode"]}
        self.write_json(self.base / "environment.json", environment)
        manifest = self.export()
        self.assertEqual(manifest["environment"]["externally_asserted_commands"],
                         ["not an acquisition or export command"])
        self.assertNotIn("not an acquisition or export command", manifest["environment"]["commands"])
        self.assertIn("not reconstructed or evidence-verified",
                      manifest["environment"]["command_provenance"]["externally_asserted_commands"])

    def test_symbolic_link_product_ancestors_fail_before_outside_content_is_staged(self):
        for relative in ("Build", "Build/Products", "Build/Products/Release-iphonesimulator"):
            with self.subTest(relative=relative):
                path = self.derived_data / relative
                external = self.base / ("external-" + relative.replace("/", "-"))
                path.rename(external)
                path.symlink_to(external, target_is_directory=True)
                output = self.base / ("linked-" + relative.replace("/", "-"))
                with self.assertRaisesRegex(ExportError, "real directory"):
                    self.export(output)
                self.assertFalse(output.exists())
                path.unlink()
                external.rename(path)

    def test_malformed_environment_and_unexpected_type_errors_use_controlled_exit_2(self):
        for toolchain in (None, "untyped", {"xcode": None}):
            with self.subTest(toolchain=toolchain):
                environment = copy.deepcopy(self.environment)
                environment["toolchain"] = toolchain
                self.write_json(self.base / "environment.json", environment)
                stderr = io.StringIO()
                with redirect_stderr(stderr):
                    self.assertEqual(main(["--run-root", str(self.root), "--derived-data", str(self.derived_data),
                                           "--environment", str(self.base / "environment.json"),
                                           "--output", str(self.output)]), 2)
                self.assertIn("Toolchain", stderr.getvalue())
                self.assertNotIn("Traceback", stderr.getvalue())
                self.assertFalse(self.output.exists())
        self.write_json(self.base / "environment.json", self.environment)
        with mock.patch("export_iteration_manifest.load_run", side_effect=TypeError("unexpected input shape")):
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                self.assertEqual(main(["--run-root", str(self.root), "--derived-data", str(self.derived_data),
                                       "--environment", str(self.base / "environment.json"),
                                       "--output", str(self.output)]), 2)
            self.assertIn("unexpected input shape", stderr.getvalue())
            self.assertNotIn("Traceback", stderr.getvalue())

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
