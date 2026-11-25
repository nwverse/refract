import copy
import hashlib
import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from paired_report import EvidenceError, ITERATIONS, checked_iteration, make_report, markdown, percentile


class PairedReportTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "raw").mkdir()
        self.build_path = "raw/refract-build-provenance.json"
        (self.root / self.build_path).write_bytes(b"synthetic build identity")
        self.build_hash = hashlib.sha256((self.root / self.build_path).read_bytes()).hexdigest()
        self.manifest = {
            "schema": 2,
            "platform": "ios",
            "environment": {
                "platform": "ios",
                "target_label": "SIMULATOR",
                "device_result": False,
                "source_revision": "a" * 40,
                "build_provenance": {"path": self.build_path, "sha256": self.build_hash},
                "toolchain": {"xcode": "test"},
                "build_configuration": {"name": "Release"},
                "target": {"model": "test", "os_version": "test", "architecture": "test"},
                "commands": ["xcresulttool get test-results metrics"],
            },
            "artifacts": [self.artifact(self.build_path, "shared", "build", 2, "xcresult", "build-provenance")],
            "measurements": [],
            "resources": [],
        }
        for variant in ("generated", "reference"):
            for scenario in ("startup", "scroll", "stateUpdate"):
                metric = "startupMs" if scenario == "startup" else "frameIntervalMs"
                for iteration in range(2, 31):
                    for kind, name, role in (("xctrace", f"{scenario}.trace.zip", "profiler"),
                                             ("xcode-metric-json",
                                              "metrics.json" if scenario == "startup" else "native-samples.json",
                                              "timing")):
                        path = f"raw/{variant}-{scenario}-{iteration}-{name}"
                        (self.root / path).write_bytes(b"synthetic native evidence")
                        self.manifest["artifacts"].append(self.artifact(path, variant, scenario, iteration, kind, role))
                    if scenario != "startup":
                        path = f"raw/{variant}-{scenario}-{iteration}-memory.json"
                        (self.root / path).write_bytes(b"synthetic memory export")
                        self.manifest["artifacts"].append(self.artifact(path, variant, scenario, iteration,
                                                                       "xcode-metric-json", "memory"))
                        self.manifest["resources"].append({
                            "platform": "ios", "variant": variant, "scenario": scenario,
                            "iteration": iteration, "metric": "residentMemoryBytes", "bytes": 1024,
                            "artifacts": [path],
                        })
                    definition = ("XCTApplicationLaunchMetric" if scenario == "startup"
                                  else "CADisplayLink.targetTimestamp-timestamp")
                    metric_path = (f"raw/{variant}-{scenario}-{iteration}-metrics.json" if scenario == "startup"
                                   else f"raw/{variant}-{scenario}-{iteration}-native-samples.json")
                    self.manifest["measurements"].append({
                        "platform": "ios", "variant": variant, "scenario": scenario,
                        "iteration": iteration, "metric": metric, "unit": "ms", "value": 10.0,
                        "definition": definition,
                        **({} if scenario == "startup" else {"aggregation": "p99", "source_samples": [9.0, 10.0]}),
                        "artifacts": [metric_path, f"raw/{variant}-{scenario}-{iteration}-{scenario}.trace.zip"],
                    })
            path = f"raw/{variant}-startup-2-binary.json"
            (self.root / path).write_bytes(b"synthetic installed binary export")
            self.manifest["artifacts"].append(self.artifact(path, variant, "startup", 2, "xcode-metric-json", "binary"))
            self.manifest["resources"].append({
                "platform": "ios", "variant": variant, "scenario": "startup", "iteration": 2,
                "metric": "installedBinaryBytes", "bytes": 4096, "artifacts": [path],
            })

    def artifact(self, path, variant, scenario, iteration, kind, role):
        raw = self.root / path
        return {"path": path, "kind": kind, "role": role, "variant": variant, "scenario": scenario,
                "iteration": iteration, "bytes": raw.stat().st_size,
                "sha256": hashlib.sha256(raw.read_bytes()).hexdigest(), "source_revision": "a" * 40,
                "build_provenance_sha256": self.build_hash}

    def test_complete_paired_samples_pass_without_claiming_device_gate(self):
        report = make_report(self.manifest, self.root)
        self.assertEqual(report["schema"], 2)
        self.assertEqual(report["status"], "pass")
        self.assertEqual(report["target_label"], "SIMULATOR")
        self.assertFalse(report["physical_device_gate_satisfied"])
        self.assertEqual(len(report["comparisons"]), 3)
        self.assertTrue(all(row["iterations"] == list(range(2, 31)) for row in report["comparisons"]))
        self.assertEqual(len(report["resource_pairs"]), 59)
        self.assertEqual(report["resource_pairs"][-1]["metric"], "installedBinaryBytes")
        self.assertIn("SIMULATOR RESULTS — not device results", markdown(report))

    def test_iteration_domain_is_exactly_2_through_30(self):
        self.assertEqual(list(ITERATIONS), list(range(2, 31)))
        for iteration in (0, 1, 31, True, 2.0, "30"):
            with self.subTest(iteration=iteration), self.assertRaisesRegex(EvidenceError, "2...30"):
                checked_iteration(iteration)
        self.manifest["measurements"] = [entry for entry in self.manifest["measurements"] if entry["iteration"] != 30]
        with self.assertRaisesRegex(EvidenceError, "iteration30"):
            make_report(self.manifest, self.root)

    def test_boolean_iteration_is_rejected(self):
        self.manifest["measurements"][0]["iteration"] = True
        with self.assertRaisesRegex(EvidenceError, "2...30"):
            make_report(self.manifest, self.root)

        self.manifest["schema"] = 1
        with self.assertRaisesRegex(EvidenceError, "schema 2"):
            make_report(self.manifest, self.root)

    def test_startup_requires_xctest_launch_duration_not_first_display(self):
        measurement = next(entry for entry in self.manifest["measurements"] if entry["scenario"] == "startup")
        for definition in ("firstDisplay", "CACurrentMediaTime", "scene-activation", "launch-to-first-frame"):
            manifest = copy.deepcopy(self.manifest)
            entry = next(entry for entry in manifest["measurements"] if entry["scenario"] == "startup")
            entry["definition"] = definition
            with self.subTest(definition=definition), self.assertRaisesRegex(EvidenceError, "firstDisplay is not"):
                make_report(manifest, self.root)
        measurement["artifacts"] = [path for path in measurement["artifacts"] if "metrics" not in path]
        with self.assertRaisesRegex(EvidenceError, "metrics.json"):
            make_report(self.manifest, self.root)

    def test_display_array_cannot_be_passed_off_as_an_unreduced_timing_scalar(self):
        manifest = copy.deepcopy(self.manifest)
        measurement = next(entry for entry in manifest["measurements"] if entry["scenario"] == "scroll")
        measurement.pop("aggregation")
        with self.assertRaisesRegex(EvidenceError, "explicit per-iteration p99"):
            make_report(manifest, self.root)
        measurement = next(entry for entry in self.manifest["measurements"] if entry["scenario"] == "scroll")
        measurement["artifacts"] = [path for path in measurement["artifacts"] if "native-samples" not in path]
        with self.assertRaisesRegex(EvidenceError, "native-samples.json"):
            make_report(self.manifest, self.root)

    def test_inconsistent_frame_reduction_is_rejected(self):
        measurement = next(entry for entry in self.manifest["measurements"] if entry["scenario"] == "scroll")
        measurement["value"] = 9.5
        with self.assertRaisesRegex(EvidenceError, "declared p99"):
            make_report(self.manifest, self.root)

    def test_frame_reduction_uses_nearest_rank_and_preserves_thresholds(self):
        self.assertEqual(percentile([1.0, 8.0, 30.0], 0.99), 30.0)
        self.assertEqual(percentile([1.0, 8.0, 30.0], 0.5), 8.0)
        startup = [entry for entry in self.manifest["measurements"] if entry["scenario"] == "startup"]
        for entry in startup:
            entry["value"] = 20.0
        for entry in startup:
            if entry["variant"] == "generated":
                entry["value"] = 20.6
        next(entry for entry in reversed(startup) if entry["variant"] == "generated")["value"] = 40.0
        report = make_report(self.manifest, self.root)
        self.assertEqual(report["status"], "fail")
        self.assertEqual(report["threshold"], {"relative_percent": 5.0, "absolute_ms": 0.1, "conjunction": "AND"})
        row = next(row for row in report["comparisons"] if row["scenario"] == "startup")
        self.assertFalse(row["p50"]["regressed"])
        self.assertTrue(row["p99"]["regressed"])
        self.assertIn("Result: FAIL", markdown(report))

    def test_revision_and_build_provenance_cannot_be_backfilled(self):
        artifact = next(entry for entry in self.manifest["artifacts"] if entry["role"] == "timing")
        artifact["source_revision"] = "b" * 40
        with self.assertRaisesRegex(EvidenceError, "another revision or build"):
            make_report(self.manifest, self.root)
        artifact["source_revision"] = "a" * 40
        artifact["build_provenance_sha256"] = "0" * 64
        with self.assertRaisesRegex(EvidenceError, "another revision or build"):
            make_report(self.manifest, self.root)
        self.manifest["artifacts"].remove(artifact)
        self.manifest["environment"]["source_revision"] = "HEAD"
        with self.assertRaisesRegex(EvidenceError, "source revision"):
            make_report(self.manifest, self.root)

    def test_checksum_and_build_manifest_integrity_are_retained(self):
        artifact = next(entry for entry in self.manifest["artifacts"] if entry["role"] == "profiler")
        artifact["sha256"] = "0" * 64
        with self.assertRaisesRegex(EvidenceError, "checksum mismatch"):
            make_report(self.manifest, self.root)
        self.manifest["artifacts"].remove(artifact)
        self.manifest["environment"]["build_provenance"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(EvidenceError, "another revision or build"):
            make_report(self.manifest, self.root)

    def test_missing_one_iteration_is_not_a_pass(self):
        self.manifest["measurements"].pop()
        with self.assertRaisesRegex(EvidenceError, "Missing or duplicate raw sample"):
            make_report(self.manifest, self.root)

    def test_one_trace_cannot_be_reused_for_ten_iterations(self):
        kept = [entry for entry in self.manifest["artifacts"] if entry["role"] != "profiler"
                or entry["iteration"] == 2]
        self.manifest["artifacts"] = kept
        with self.assertRaisesRegex(EvidenceError, "Missing or ambiguous native evidence reference"):
            make_report(self.manifest, self.root)

    def test_duplicate_sample_is_rejected(self):
        self.manifest["measurements"].append(self.manifest["measurements"][0])
        with self.assertRaisesRegex(EvidenceError, "Missing or duplicate raw sample"):
            make_report(self.manifest, self.root)

    def test_mismatched_variant_binding_is_rejected(self):
        entry = self.manifest["measurements"][0]
        entry["artifacts"] = [next(item["path"] for item in self.manifest["artifacts"]
                                  if item["role"] == "timing" and item["variant"] == "reference")]
        with self.assertRaisesRegex(EvidenceError, "not bound"):
            make_report(self.manifest, self.root)

    def test_empty_missing_changed_or_non_native_trace_is_rejected(self):
        for mutation in ("bytes", "checksum", "missing", "directory"):
            manifest = copy.deepcopy(self.manifest)
            entry = next(item for item in manifest["artifacts"] if item["role"] == "profiler")
            if mutation == "bytes":
                entry["bytes"] += 1
            elif mutation == "checksum":
                entry["sha256"] = "0" * 64
            elif mutation == "missing":
                entry["path"] = "raw/missing.trace.zip"
            else:
                (self.root / "raw/directory.trace.zip").mkdir()
                entry["path"] = "raw/directory.trace.zip"
                entry["bytes"] = 1
            with self.subTest(mutation=mutation), self.assertRaises(EvidenceError):
                make_report(manifest, self.root)

    def test_zero_infinite_negative_or_wrong_unit_values_are_rejected(self):
        for value in (0, -1, math.inf, math.nan, True, "16"):
            manifest = copy.deepcopy(self.manifest)
            manifest["measurements"][0]["value"] = value
            with self.subTest(value=value), self.assertRaises(EvidenceError):
                make_report(manifest, self.root)
        self.manifest["measurements"][0]["unit"] = "seconds"
        with self.assertRaisesRegex(EvidenceError, "milliseconds"):
            make_report(self.manifest, self.root)

    def test_small_absolute_change_does_not_fail_at_the_same_quantile(self):
        for entry in self.manifest["measurements"]:
            if entry["variant"] == "generated" and entry["scenario"] == "startup":
                entry["value"] = 10.06
        self.assertEqual(make_report(self.manifest, self.root)["status"], "pass")

    def test_memory_and_binary_are_paired_in_bytes_with_role_provenance(self):
        report = make_report(self.manifest, self.root)
        memory = next(pair for pair in report["resource_pairs"] if pair["metric"] == "residentMemoryBytes")
        binary = next(pair for pair in report["resource_pairs"] if pair["metric"] == "installedBinaryBytes")
        self.assertEqual((memory["reference"], memory["generated"], memory["delta"]), (1024, 1024, 0))
        self.assertEqual((binary["reference"], binary["generated"], binary["delta"]), (4096, 4096, 0))
        self.manifest["resources"] = [dict(resource, bytes=1.5) if resource["metric"] == "residentMemoryBytes"
                                      else resource for resource in self.manifest["resources"]]
        with self.assertRaisesRegex(EvidenceError, "integer bytes"):
            make_report(self.manifest, self.root)

    def test_missing_memory_or_binary_pair_is_not_a_pass(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["resources"] = [resource for resource in manifest["resources"]
                                 if not (resource["metric"] == "residentMemoryBytes"
                                         and resource["iteration"] == 30 and resource["scenario"] == "scroll"
                                         and resource["variant"] == "reference")]
        with self.assertRaisesRegex(EvidenceError, "resident memory pair.*30"):
            make_report(manifest, self.root)
        self.manifest["resources"] = [resource for resource in self.manifest["resources"]
                                      if resource["metric"] != "installedBinaryBytes"]
        self.manifest["resources"] = [resource for resource in self.manifest["resources"]
                                      if resource["metric"] != "installedBinaryBytes"]
        with self.assertRaisesRegex(EvidenceError, "installed binary"):
            make_report(self.manifest, self.root)

    def test_binary_cannot_be_filled_by_other_iterations_or_scenarios(self):
        reference_binary = next(resource for resource in self.manifest["resources"]
                                if resource["metric"] == "installedBinaryBytes" and resource["variant"] == "reference")
        self.manifest["resources"].remove(reference_binary)
        other_iteration = copy.deepcopy(reference_binary)
        other_iteration["iteration"] = 3
        other_artifact = next(artifact for artifact in self.manifest["artifacts"]
                              if artifact["path"] == reference_binary["artifacts"][0])
        other_artifact["iteration"] = 3
        self.manifest["resources"].append(other_iteration)
        with self.assertRaisesRegex(EvidenceError, "same iteration's build identity"):
            make_report(self.manifest, self.root)
        other_artifact["iteration"] = 2
        other_iteration["iteration"] = 2
        other_artifact["scenario"] = "scroll"
        other_iteration["scenario"] = "scroll"
        with self.assertRaisesRegex(EvidenceError, "one scenario"):
            make_report(self.manifest, self.root)

    def test_memory_cannot_reference_a_timing_or_binary_artifact(self):
        memory = next(resource for resource in self.manifest["resources"] if resource["metric"] == "residentMemoryBytes")
        artifact = next(artifact for artifact in self.manifest["artifacts"] if artifact["path"] == memory["artifacts"][0])
        for role in ("timing", "binary"):
            artifact["role"] = role
            with self.subTest(role=role), self.assertRaisesRegex(EvidenceError, "mismatched native provenance"):
                make_report(self.manifest, self.root)

    def test_cross_target_is_rejected(self):
        self.manifest["environment"]["target_label"] = "DEVICE"
        with self.assertRaisesRegex(EvidenceError, "disagree"):
            make_report(self.manifest, self.root)

    def test_harmony_uses_vendor_native_metrics_with_explicit_scalar_definitions(self):
        self.manifest["platform"] = "harmonyos"
        self.manifest["environment"]["platform"] = "harmonyos"
        for artifact in self.manifest["artifacts"]:
            artifact["kind"] = "vendor-metric-json" if artifact["kind"] != "xctrace" else "vendor-trace"
        for measurement in self.manifest["measurements"]:
            measurement["platform"] = "harmonyos"
            measurement["metric"] = "startupMs" if measurement["scenario"] == "startup" else "frameDurationMs"
            measurement["definition"] = ("native-launch-duration" if measurement["scenario"] == "startup"
                                         else "native-frame-duration")
            if measurement["scenario"] == "startup":
                measurement.update(launch_start_timestamp_ms=90.0, first_frame_timestamp_ms=100.0, timestamp_unit="ms")
        for resource in self.manifest["resources"]:
            resource["platform"] = "harmonyos"
        report = make_report(self.manifest, self.root)
        self.assertEqual(report["platform"], "harmonyos")
        self.assertEqual(report["comparisons"][1]["metric"], "frameDurationMs")
        startup = next(entry for entry in self.manifest["measurements"] if entry["scenario"] == "startup")
        startup["launch_start_timestamp_ms"] = 110.0
        with self.assertRaisesRegex(EvidenceError, "subtract native first-frame and launch timestamps"):
            make_report(self.manifest, self.root)

    def test_harmony_needs_vendor_trace_not_an_ios_trace(self):
        self.manifest["platform"] = "harmonyos"
        self.manifest["environment"]["platform"] = "harmonyos"
        with self.assertRaisesRegex(EvidenceError, "not a native harmonyos artifact"):
            make_report(self.manifest, self.root)


if __name__ == "__main__":
    unittest.main()
