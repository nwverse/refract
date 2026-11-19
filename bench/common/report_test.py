import hashlib
import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from paired_report import EvidenceError, make_report, markdown


class PairedReportTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "raw").mkdir()
        self.manifest = {
            "schema": 1,
            "platform": "ios",
            "environment": {
                "platform": "ios",
                "target_label": "SIMULATOR",
                "device_result": False,
                "source_revision": "a" * 40,
                "toolchain": {"xcode": "test"},
                "build_configuration": {"name": "Release"},
                "target": {"model": "test", "os_version": "test", "architecture": "test"},
                "commands": ["xcresulttool get test-results metrics"],
            },
            "artifacts": [],
            "measurements": [],
            "resources": [],
        }
        for variant in ("generated", "reference"):
            for scenario in ("startup", "scroll", "stateUpdate"):
                metric = "startupMs" if scenario == "startup" else "frameIntervalMs"
                for iteration in range(30):
                    for kind in ("xctrace", "xcode-metric-json"):
                        path = f"raw/{variant}-{scenario}-{iteration}-{kind}"
                        (self.root / path).write_bytes(b"native evidence")
                        self.manifest["artifacts"].append(self.artifact(path, variant, scenario, iteration, kind))
                    if scenario != "startup":
                        self.manifest["resources"].append({
                            "platform": "ios", "variant": variant, "scenario": scenario,
                            "iteration": iteration, "metric": "residentMemoryBytes", "bytes": 1024,
                            "artifacts": [f"raw/{variant}-{scenario}-{iteration}-xcode-metric-json"],
                        })
                    if iteration == 0:
                        self.manifest["resources"].append({
                            "platform": "ios", "variant": variant, "scenario": scenario,
                            "iteration": iteration, "metric": "installedBinaryBytes", "bytes": 4096,
                            "artifacts": [f"raw/{variant}-{scenario}-{iteration}-xcode-metric-json"],
                        })
                    self.manifest["measurements"].append({
                        "platform": "ios", "variant": variant, "scenario": scenario,
                        "iteration": iteration, "metric": metric, "unit": "ms", "samples": [10.0],
                        "artifacts": [f"raw/{variant}-{scenario}-{iteration}-xcode-metric-json",
                                      f"raw/{variant}-{scenario}-{iteration}-xctrace"],
                    })

    def artifact(self, path, variant, scenario, iteration, kind):
        raw = self.root / path
        return {"path": path, "kind": kind, "variant": variant, "scenario": scenario,
                "iteration": iteration, "bytes": raw.stat().st_size, "sha256": hashlib.sha256(raw.read_bytes()).hexdigest()}

    def test_complete_paired_samples_pass_without_claiming_device_gate(self):
        report = make_report(self.manifest, self.root)
        self.assertEqual(report["status"], "pass")
        self.assertEqual(report["target_label"], "SIMULATOR")
        self.assertFalse(report["physical_device_gate_satisfied"])
        self.assertEqual(len(report["comparisons"]), 3)
        self.assertIn("SIMULATOR RESULTS — not device results", markdown(report))

    def test_missing_one_iteration_is_not_a_pass(self):
        self.manifest["measurements"].pop()
        with self.assertRaisesRegex(EvidenceError, "Missing or duplicate raw sample"):
            make_report(self.manifest, self.root)

    def test_one_trace_cannot_be_reused_for_ten_iterations(self):
        kept = [entry for entry in self.manifest["artifacts"] if entry["kind"] != "xctrace"
                or entry["iteration"] == 0]
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
                                  if item["kind"] == "xcode-metric-json" and item["variant"] == "reference")]
        with self.assertRaisesRegex(EvidenceError, "not bound"):
            make_report(self.manifest, self.root)

    def test_empty_missing_changed_or_non_native_trace_is_rejected(self):
        for mutation in ("bytes", "checksum", "missing", "directory"):
            manifest = json.loads(json.dumps(self.manifest))
            entry = next(item for item in manifest["artifacts"] if item["kind"] == "xctrace")
            if mutation == "bytes":
                entry["bytes"] += 1
            elif mutation == "checksum":
                entry["sha256"] = "0" * 64
            elif mutation == "missing":
                entry["path"] = "raw/missing.trace"
            else:
                (self.root / "raw").mkdir(exist_ok=True)
                (self.root / "raw/directory.trace").mkdir()
                entry["path"] = "raw/directory.trace"
                entry["bytes"] = 1
            with self.subTest(mutation=mutation), self.assertRaises(EvidenceError):
                make_report(manifest, self.root)

    def test_zero_infinite_negative_or_wrong_unit_samples_are_rejected(self):
        for value in (0, -1, math.inf, math.nan, True, "16"):
            manifest = json.loads(json.dumps(self.manifest))
            manifest["measurements"][0]["samples"][0] = value
            with self.subTest(value=value), self.assertRaises(EvidenceError):
                make_report(manifest, self.root)
        self.manifest["measurements"][0]["unit"] = "seconds"
        with self.assertRaisesRegex(EvidenceError, "milliseconds"):
            make_report(self.manifest, self.root)

    def test_cross_target_and_missing_revision_are_rejected(self):
        self.manifest["environment"]["target_label"] = "DEVICE"
        with self.assertRaisesRegex(EvidenceError, "disagree"):
            make_report(self.manifest, self.root)
        self.manifest["environment"]["target_label"] = "SIMULATOR"
        self.manifest["environment"]["source_revision"] = "HEAD"
        with self.assertRaisesRegex(EvidenceError, "source revision"):
            make_report(self.manifest, self.root)

    def test_both_regression_conditions_are_required(self):
        startup = [entry for entry in self.manifest["measurements"] if entry["scenario"] == "startup"]
        for entry in startup:
            entry["samples"] = [20.0]
        for entry in startup:
            if entry["variant"] == "generated":
                entry["samples"] = [20.6]
        # p50 is within the absolute screening limit, but the final iteration
        # crosses both limits and must still fail the nearest-rank p99 gate.
        next(entry for entry in reversed(startup) if entry["variant"] == "generated")["samples"] = [40.0]
        report = make_report(self.manifest, self.root)
        self.assertEqual(report["status"], "fail")
        row = next(row for row in report["comparisons"] if row["scenario"] == "startup")
        self.assertFalse(row["p50"]["regressed"])
        self.assertTrue(row["p99"]["regressed"])
        self.assertIn("Result: FAIL", markdown(report))

    def test_small_absolute_change_does_not_fail_at_the_same_quantile(self):
        for entry in self.manifest["measurements"]:
            if entry["variant"] == "generated":
                entry["samples"] = [10.06]
        self.assertEqual(make_report(self.manifest, self.root)["status"], "pass")

    def test_memory_and_binary_sizes_are_bytes_with_native_provenance(self):
        report = make_report(self.manifest, self.root)
        self.assertTrue(any(resource["bytes"] == 4096 for resource in report["resources"]))
        self.manifest["resources"] = [dict(resource, bytes=1.5) if resource["metric"] == "residentMemoryBytes"
                                      else resource for resource in self.manifest["resources"]]
        with self.assertRaisesRegex(EvidenceError, "integer bytes"):
            make_report(self.manifest, self.root)

    def test_missing_memory_or_binary_size_is_not_a_pass(self):
        memory = self.manifest["resources"].pop(0)
        with self.assertRaisesRegex(EvidenceError, "resident memory|installed binary size"):
            make_report(self.manifest, self.root)
        self.manifest["resources"].insert(0, memory)
        self.manifest["resources"] = [resource for resource in self.manifest["resources"]
                                      if resource["metric"] != "installedBinaryBytes"]
        with self.assertRaisesRegex(EvidenceError, "installed binary size"):
            make_report(self.manifest, self.root)

    def test_harmony_needs_vendor_trace_not_an_ios_trace(self):
        self.manifest["platform"] = "harmonyos"
        self.manifest["environment"]["platform"] = "harmonyos"
        with self.assertRaisesRegex(EvidenceError, "not a native harmonyos artifact"):
            make_report(self.manifest, self.root)


if __name__ == "__main__":
    unittest.main()
