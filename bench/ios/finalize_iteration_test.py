#!/usr/bin/env python3
"""Synthetic acyclic finalizer tests; no native acquisition or target is used."""

from __future__ import annotations

import copy
import hashlib
import io
import json
import os
import shutil
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from export_iteration_manifest import (BINARY_PATH, METRICS_PATH, ExportError, RunContext, export_manifest,
                                       load_environment, load_run, verify_retained_files)
from export_iteration_manifest_test import IterationManifestFixture
from finalize_iteration import finalize_iteration, main


class IterationFinalizerTest(unittest.TestCase):
    def setUp(self):
        self.fixture = IterationManifestFixture()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.runs = sorted(self.fixture.root.iterdir())
        for run in self.runs:
            (run / "accepted-evidence.json").unlink()
            (run / "retained-file-hashes.json").unlink()
        self.before = {run: self.files(run) for run in self.runs}

    def files(self, run):
        return {path.relative_to(run).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in run.rglob("*") if path.is_file()}

    def assert_unchanged(self, run):
        self.assertEqual(self.files(run), self.before[run])

    def test_real_cli_publishes_one_bound_startup_without_changing_inputs(self):
        run = self.fixture.run_path("generated", "startup", 2)
        metadata = self.fixture.base / f"metadata-{run.name}.json"
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            status = main(["--run-directory", str(run), "--derived-data", str(self.fixture.derived_data),
                           "--metadata", str(metadata)])
        self.assertEqual(status, 0, stderr.getvalue())
        self.assertEqual(json.loads(stdout.getvalue())["status"], "accepted-native-iteration")
        accepted = verify_retained_files(run)
        self.assertEqual(accepted["producer_binding"]["protocol"], "ios-producer-evidence-v1")
        self.assertNotIn("native_launch_metric", json.loads((run / "raw/iteration-trace.json").read_text()))
        self.assertNotIn("retained-file-hashes.json", accepted["retained_files"])
        for relative, sha256 in self.before[run].items():
            self.assertEqual(hashlib.sha256((run / relative).read_bytes()).hexdigest(), sha256)
        self.assertEqual(self.files(run)["accepted-evidence.json"],
                         json.loads((run / "retained-file-hashes.json").read_text())["files"][
                             "accepted-evidence.json"]["sha256"])
        before = self.files(run)
        with self.assertRaisesRegex(ExportError, "Refusing to replace"):
            finalize_iteration(run, self.fixture.derived_data, metadata)
        self.assertEqual(self.files(run), before)

    def test_full_174_measurement_and_118_resource_contract(self):
        for run in self.runs:
            finalize_iteration(run, self.fixture.derived_data,
                               self.fixture.base / f"metadata-{run.name}.json")
        manifest = self.fixture.export()
        self.assertEqual(len(manifest["measurements"]), 174)
        self.assertEqual(len(manifest["resources"]), 118)
        for run in self.runs:
            after = self.files(run)
            for relative, sha256 in self.before[run].items():
                self.assertEqual(after[relative], sha256, relative)
            accepted = json.loads((run / "accepted-evidence.json").read_text())
            binding = accepted["producer_binding"]
            self.assertEqual(binding["receipt"]["sha256"], after["raw/iteration-trace.json"])
            self.assertEqual(binding["configuration"]["sha256"], after["iteration-trace-config.json"])
            if accepted["scenario"] == "startup":
                self.assertEqual(binding["normalized_metrics"]["sha256"], after[METRICS_PATH])
                normalized = json.loads((run / METRICS_PATH).read_text())
                self.assertEqual(normalized["provenance"]["trace_receipt_sha256"],
                                 binding["receipt"]["sha256"])
                self.assertEqual(binding["native_process_packets"],
                                 normalized["provenance"]["native_process_packets"])

    def test_incomplete_or_tampered_producer_input_publishes_nothing(self):
        cases = [
            ("missing-metric", "raw/metrics.json", None),
            ("missing-native-packet", "control/native-process.json", None),
            ("missing-alias", BINARY_PATH, None),
            ("wrong-native-session", "control/native-process.json", ("session", 2)),
            ("wrong-receipt-hash", METRICS_PATH, ("provenance.trace_receipt_sha256", "0" * 64)),
            ("wrong-resource-alias", "raw/iteration-trace.json",
             ("native_resources.exports.installedBinaryBytes.path", "raw/native-memory.json")),
            ("wrong-configuration", "iteration-trace-config.json", ("iteration", 30)),
        ]
        for index, (name, relative, mutation) in enumerate(cases):
            with self.subTest(name=name):
                root = self.fixture.base / f"negative-{index}"
                root.mkdir()
                run = root / "generated-startup-2"
                original = self.fixture.run_path("generated", "startup", 2)
                shutil.copytree(original, run)
                finalize_iteration(run, self.fixture.derived_data,
                                   self.fixture.base / f"metadata-{original.name}.json")
                self.fixture.rebind_run(run)
                (run / "accepted-evidence.json").unlink()
                (run / "retained-file-hashes.json").unlink()
                metadata = self.fixture.base / f"negative-{index}.json"
                self.fixture.write_json(metadata, {"target": self.fixture.target,
                                                   "toolchain": self.fixture.toolchain,
                                                   "commands": ["synthetic input"]})
                before = self.files(run)
                if mutation is None:
                    (run / relative).unlink()
                else:
                    payload = json.loads((run / relative).read_text())
                    key, value = mutation
                    target = payload
                    parts = key.split(".")
                    for part in parts[:-1]:
                        target = target[part]
                    target[parts[-1]] = value
                    self.fixture.write_json(run / relative, payload)
                before = self.files(run)
                with self.assertRaises((ExportError, KeyError, OSError)):
                    finalize_iteration(run, self.fixture.derived_data, metadata)
                self.assertEqual(self.files(run), before)
                stderr = io.StringIO()
                with redirect_stderr(stderr):
                    self.assertEqual(main(["--run-directory", str(run), "--derived-data",
                                           str(self.fixture.derived_data), "--metadata", str(metadata)]), 2)
                self.assertNotIn("Traceback", stderr.getvalue())
                self.assertEqual(self.files(run), before)

    def test_reader_rejects_missing_stale_binding_and_incomplete_publication(self):
        run = self.fixture.run_path("generated", "startup", 2)
        finalize_iteration(run, self.fixture.derived_data, self.fixture.base / f"metadata-{run.name}.json")
        for name, change in (
                ("missing-binding", lambda accepted: accepted.pop("producer_binding")),
                ("stale-receipt", lambda accepted: accepted["producer_binding"]["receipt"].update(sha256="0" * 64)),
                ("stale-metric", lambda accepted: accepted["producer_binding"]["normalized_metrics"].update(
                    sha256="0" * 64)),
                ("stale-packet", lambda accepted: accepted["producer_binding"]["native_process_packets"][
                    "native_process"].update(sha256="0" * 64)),
                ("stale-alias", lambda accepted: accepted["producer_binding"]["resources"]["aliases"][
                    "installedBinaryBytes"].update(sha256="0" * 64)),
        ):
            with self.subTest(name=name):
                path = run / "accepted-evidence.json"
                original = path.read_bytes()
                accepted = json.loads(original)
                change(accepted)
                path.write_text(json.dumps(accepted))
                with self.assertRaisesRegex(ExportError, "binding|checksum"):
                    load_run(run, self.fixture.derived_data, RunContext(
                        self.fixture.revision, self.fixture.build_hash, self.fixture.target,
                        self.fixture.toolchain, {}), "RefractBench.xctestrun")
                path.write_bytes(original)
                verify_retained_files(run)
        inventory = run / "retained-file-hashes.json"
        content = inventory.read_bytes()
        inventory.unlink()
        with self.assertRaisesRegex(ExportError, "Cannot read retained JSON"):
            verify_retained_files(run)
        inventory.write_bytes(content)
        verify_retained_files(run)


    def test_actual_runner_and_launch_export_feed_the_offline_finalizer(self):
        from launch_metric import export_launch_metric
        from launch_metric_test import synthetic_metrics, synthetic_tests
        from iteration_trace_runner_test import IterationTraceRunnerTest

        producer = IterationTraceRunnerTest("test_actual_startup_resource_capture_composes_with_launch_export")
        producer.setUp()
        self.addCleanup(producer.doCleanups)
        captured = producer.capture_startup_resources()
        run = producer.root

        def export_pipe(command, **options):
            import subprocess
            payload = synthetic_tests() if " tests " in " ".join(command) else synthetic_metrics()
            process = subprocess.Popen([sys.executable, "-I", "-c",
                                        "import os,sys; data=sys.stdin.buffer.read(); os.write(1,data)"],
                                       stdin=subprocess.PIPE, **options)
            process.stdin.write(json.dumps(payload).encode())
            process.stdin.close()
            return process

        exported = export_launch_metric(run, variant="generated", revision="a" * 40, iteration=2,
                                        target_udid="synthetic-target", run_command=export_pipe)
        device = {"architecture": "arm64", "deviceId": "synthetic-target", "deviceName": "Synthetic simulator",
                  "modelName": "com.example.simulator", "osVersion": "Synthetic OS", "platform": "iOS Simulator"}
        raw_metrics = synthetic_metrics()
        raw_metrics[0]["testRuns"][0]["device"] = device
        self.fixture.write_json(run / "raw/exports/xctest-metrics.json", raw_metrics)
        normalized = json.loads((run / exported["path"]).read_text())
        normalized["provenance"]["raw_exports"]["xctest-metrics.json"]["sha256"] = hashlib.sha256(
            (run / "raw/exports/xctest-metrics.json").read_bytes()).hexdigest()
        self.fixture.write_json(run / exported["path"], normalized)
        self.fixture.write_json(run / "raw/exports/xctest-summary.json", {
            "devicesAndConfigurations": [{"device": device}], "result": "Passed",
            "passedTests": 1, "failedTests": 0, "skippedTests": 0})
        self.fixture.write_json(run / "target.json", {"target_label": "SIMULATOR", "device_result": False,
                                                       "model": device["modelName"], "state": "Booted",
                                                       "udid": device["deviceId"]})
        self.fixture.write_json(run / "simulators.json", {"devices": {"synthetic-runtime": [{
            "udid": device["deviceId"], "name": device["deviceName"], "state": "Booted",
            "deviceTypeIdentifier": device["modelName"], "isAvailable": True}]}})
        self.fixture.write_json(run / "targets.json", {"devices": [{
            "identifier": device["deviceId"],
            "deviceProperties": {"bootState": "booted", "name": device["deviceName"],
                                 "osVersionNumber": device["osVersion"]},
            "hardwareProperties": {"udid": device["deviceId"], "reality": "simulated",
                                   "marketingName": device["modelName"],
                                   "cpuType": {"name": device["architecture"]}}}]})
        (run / "raw/results.xcresult.zip").write_bytes(b"synthetic result archive")
        metadata = self.fixture.base / "actual-producer-metadata.json"
        self.fixture.write_json(metadata, {"target": {"udid": device["deviceId"], "name": device["deviceName"],
                                                       "model": device["modelName"], "os_version": device["osVersion"],
                                                       "architecture": device["architecture"]},
                                           "toolchain": {"xcode": "Synthetic native toolchain"},
                                           "commands": ["synthetic already-acquired iteration"]})
        before = {path.relative_to(run).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in run.rglob("*") if path.is_file()}
        accepted = finalize_iteration(run, producer.session().derived_data, metadata)
        self.assertEqual(accepted["native_pid"], captured["pid"])
        self.assertEqual(accepted["producer_binding"]["normalized_metrics"]["sha256"], before["raw/metrics.json"])
        self.assertNotIn("native_launch_metric", json.loads((run / "raw/iteration-trace.json").read_text()))
        for relative, checksum in before.items():
            self.assertEqual(hashlib.sha256((run / relative).read_bytes()).hexdigest(), checksum)

    def test_publish_failure_removes_only_new_records_and_preserves_existing_bytes(self):
        run = self.fixture.run_path("generated", "startup", 2)
        metadata = self.fixture.base / f"metadata-{run.name}.json"
        original_link = os.link

        def fail_second_link(source, destination):
            if str(source).endswith(".retained-file-hashes.json.staging"):
                raise OSError("synthetic publication failure")
            return original_link(source, destination)

        with mock.patch("finalize_iteration.os.link", side_effect=fail_second_link):
            with self.assertRaisesRegex(OSError, "synthetic publication failure"):
                finalize_iteration(run, self.fixture.derived_data, metadata)
        self.assertEqual(self.files(run), self.before[run])
        self.assertFalse(any(path.name.endswith(".staging") for path in run.iterdir()))
        finalize_iteration(run, self.fixture.derived_data, metadata)
        before = self.files(run)
        with mock.patch("finalize_iteration.os.link", side_effect=fail_second_link):
            with self.assertRaisesRegex(ExportError, "Refusing to replace"):
                finalize_iteration(run, self.fixture.derived_data, metadata)
        self.assertEqual(self.files(run), before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
