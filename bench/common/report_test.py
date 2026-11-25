import copy
import hashlib
import json
import math
import plistlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from paired_report import EvidenceError, ITERATIONS, checked_iteration, make_report, markdown, percentile
from build_provenance import BUNDLE_NAMES, original_build_provenance


class PairedReportTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "raw").mkdir()
        self.derived_data = self.root / "producer/DerivedData"
        self.write_original_products()
        self.build_path = "raw/refract-build-provenance.json"
        self.write_json(self.build_path, self.build_payload())
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
                "build_configuration": {"name": "Release", "target": "iphonesimulator",
                                        "derived_data": "producer/DerivedData"},
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
                        (self.root / path).write_bytes(b"synthetic profiler package") if role == "profiler" \
                            else self.write_json(path, self.timing_payload(variant, scenario, iteration))
                        self.manifest["artifacts"].append(self.artifact(path, variant, scenario, iteration, kind, role))
                    if scenario != "startup":
                        path = f"raw/{variant}-{scenario}-{iteration}-memory.json"
                        self.write_json(path, self.resource_payload(variant, scenario, iteration, "residentMemoryBytes"))
                        self.manifest["artifacts"].append(self.artifact(path, variant, scenario, iteration,
                                                                       "xcode-metric-json", "memory"))
                        self.manifest["resources"].append({
                            "platform": "ios", "variant": variant, "scenario": scenario,
                            "iteration": iteration, "metric": "residentMemoryBytes", "bytes": 1024,
                            "native_pid": 4242, "artifacts": [path],
                        })
                    definition = ("XCTApplicationLaunchMetric" if scenario == "startup"
                                  else "CADisplayLink.targetTimestamp-timestamp")
                    metric_path = (f"raw/{variant}-{scenario}-{iteration}-metrics.json" if scenario == "startup"
                                   else f"raw/{variant}-{scenario}-{iteration}-native-samples.json")
                    self.manifest["measurements"].append({
                        "platform": "ios", "variant": variant, "scenario": scenario,
                        "iteration": iteration, "metric": metric, "unit": "ms", "value": 10.0,
                        "definition": definition,
                        **({} if scenario == "startup" else {"aggregation": "p99", "native_pid": 4242}),
                        "artifacts": [metric_path, f"raw/{variant}-{scenario}-{iteration}-{scenario}.trace.zip"],
                    })
            path = f"raw/{variant}-startup-2-binary.json"
            self.write_json(path, self.resource_payload(variant, "startup", 2, "installedBinaryBytes"))
            self.manifest["artifacts"].append(self.artifact(path, variant, "startup", 2, "xcode-metric-json", "binary"))
            self.manifest["resources"].append({
                "platform": "ios", "variant": variant, "scenario": "startup", "iteration": 2,
                "metric": "installedBinaryBytes", "bytes": 4096, "native_pid": None, "artifacts": [path],
            })

    def write_json(self, path, payload):
        (self.root / path).write_text(json.dumps(payload, allow_nan=False), encoding="utf-8")

    def generic_build_payload(self):
        products = {}
        for variant in ("generated", "reference"):
            data = f"{variant} product".encode()
            products[variant] = {"bundle": variant, "files": [{"path": f"{variant}/RefractBench", "bytes": len(data),
                                                                 "sha256": hashlib.sha256(data).hexdigest()}]}
        return {"schema": 1, "source_revision": "a" * 40, "configuration": "Release", "products": products}

    def use_harmony_build_provenance(self):
        self.replace_json(self.build_path, self.generic_build_payload())
        self.manifest["environment"]["build_configuration"] = {"name": "Release"}

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
            "XCODE_SCHEME_NAME": "RefractBench",
        }}}))

    def build_payload(self):
        return original_build_provenance(self.derived_data, "a" * 40)

    def timing_payload(self, variant, scenario, iteration):
        identity = {"sourceRevision": "a" * 40, "variant": variant, "scenario": scenario, "iteration": iteration}
        if scenario == "startup":
            native = {**identity, "metric": "XCTApplicationLaunchMetric", "unit": "ms", "durationMs": 10.0}
            canonical = json.dumps(native, sort_keys=True, separators=(",", ":")).encode()
            return {**native, "nativeMeasurement": native,
                    "nativeMeasurementSha256": hashlib.sha256(canonical).hexdigest()}
        return {**identity, "schema": 1, "session": 1, "pid": 4242, "completedIterations": 1,
                "recordedIteration": iteration, "frameIntervalMs": [9.0, 10.0],
                "iterationByFrame": [iteration, iteration]}

    def resource_payload(self, variant, scenario, iteration, metric):
        return {"sourceRevision": "a" * 40, "variant": variant, "scenario": scenario, "iteration": iteration,
                "metric": metric, "bytes": 1024 if metric == "residentMemoryBytes" else 4096, "unit": "bytes",
                **({"pid": 4242} if metric == "residentMemoryBytes" else {})}

    def replace_json(self, path, payload):
        self.replace_bytes(path, json.dumps(payload, allow_nan=False).encode())

    def replace_bytes(self, path, data):
        (self.root / path).write_bytes(data)
        artifact = next(entry for entry in self.manifest["artifacts"] if entry["path"] == path)
        artifact["bytes"] = (self.root / path).stat().st_size
        artifact["sha256"] = hashlib.sha256((self.root / path).read_bytes()).hexdigest()
        if path == self.build_path:
            self.build_hash = artifact["sha256"]
            self.manifest["environment"]["build_provenance"]["sha256"] = self.build_hash
            for entry in self.manifest["artifacts"]:
                entry["build_provenance_sha256"] = self.build_hash

    def set_startup_duration(self, measurement, value):
        measurement["value"] = value
        path = next(path for path in measurement["artifacts"] if path.endswith("metrics.json"))
        native = self.timing_payload(measurement["variant"], "startup", measurement["iteration"])["nativeMeasurement"]
        native["durationMs"] = value
        payload = self.timing_payload(measurement["variant"], "startup", measurement["iteration"])
        payload.update(durationMs=value, nativeMeasurement=native,
                       nativeMeasurementSha256=hashlib.sha256(
                           json.dumps(native, sort_keys=True, separators=(",", ":")).encode()).hexdigest())
        self.replace_json(path, payload)

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
        with self.assertRaisesRegex(EvidenceError, "native metric export|metrics.json"):
            make_report(self.manifest, self.root)

    def test_display_array_cannot_be_passed_off_as_an_unreduced_timing_scalar(self):
        manifest = copy.deepcopy(self.manifest)
        measurement = next(entry for entry in manifest["measurements"] if entry["scenario"] == "scroll")
        measurement.pop("aggregation")
        with self.assertRaisesRegex(EvidenceError, "explicit per-iteration p99"):
            make_report(manifest, self.root)
        measurement = next(entry for entry in self.manifest["measurements"] if entry["scenario"] == "scroll")
        measurement["artifacts"] = [path for path in measurement["artifacts"] if "native-samples" not in path]
        with self.assertRaisesRegex(EvidenceError, "native metric export|native-samples.json"):
            make_report(self.manifest, self.root)

    def test_inconsistent_frame_reduction_is_rejected(self):
        measurement = next(entry for entry in self.manifest["measurements"] if entry["scenario"] == "scroll")
        measurement["value"] = 9.5
        with self.assertRaisesRegex(EvidenceError, "raw native metric export"):
            make_report(self.manifest, self.root)

    def test_raw_first_display_timestamp_cannot_impersonate_startup_duration(self):
        measurement = self.manifest["measurements"][0]
        measurement["value"] = 12345.25
        path = next(path for path in measurement["artifacts"] if path.endswith("metrics.json"))
        self.replace_json(path, {"sourceRevision": "a" * 40, "variant": "generated", "scenario": "startup",
                                 "iteration": 2, "firstDisplay": {"clock": "CACurrentMediaTime",
                                                                  "timestamp": 12345.25}})
        with self.assertRaisesRegex(EvidenceError, "launch-duration schema|firstDisplay timestamp"):
            make_report(self.manifest, self.root)

    def test_selected_native_launch_measurement_requires_its_checksum_and_duration(self):
        measurement = self.manifest["measurements"][0]
        native = self.timing_payload("generated", "startup", 2)["nativeMeasurement"]
        path = next(path for path in measurement["artifacts"] if path.endswith("metrics.json"))
        selected = native | {"value": {"definition": "XCTApplicationLaunchMetric", "unit": "ms", "duration_ms": 10.0}}
        canonical = json.dumps(selected, sort_keys=True, separators=(",", ":")).encode()
        self.replace_json(path, {"measurements": [selected]})
        measurement["metric_selector"] = {"index": 0, "value_sha256": hashlib.sha256(canonical).hexdigest()}
        report = make_report(self.manifest, self.root)
        self.assertEqual(report["samples"][0]["value"], 10.0)
        measurement["metric_selector"]["value_sha256"] = "0" * 64
        with self.assertRaisesRegex(EvidenceError, "selector checksum"):
            make_report(self.manifest, self.root)
        measurement["metric_selector"]["value_sha256"] = hashlib.sha256(canonical).hexdigest()
        timestamp = selected | {"value": {"definition": "XCTApplicationLaunchMetric", "unit": "ms",
                                          "timestamp": 12345.25}}
        canonical = json.dumps(timestamp, sort_keys=True, separators=(",", ":")).encode()
        self.replace_json(path, {"measurements": [timestamp]})
        measurement["metric_selector"]["value_sha256"] = hashlib.sha256(canonical).hexdigest()
        with self.assertRaisesRegex(EvidenceError, "duration|timestamp"):
            make_report(self.manifest, self.root)

    def test_existing_ios_build_provenance_is_accepted_without_weakening_its_identity(self):
        payload = self.build_payload()
        self.replace_json(self.build_path, payload)
        self.assertEqual(make_report(self.manifest, self.root)["status"], "pass")
        for key, value in (("source_revision", "b" * 40), ("configuration", "Debug-iphonesimulator")):
            changed = copy.deepcopy(payload)
            changed[key] = value
            self.replace_json(self.build_path, changed)
            with self.subTest(field=key), self.assertRaisesRegex(EvidenceError, "revision|configuration|destination"):
                make_report(self.manifest, self.root)
        for field, target, value in (
                ("source_sha256", payload["source_xctestrun"], "0" * 64),
                ("product_sha256", payload["products"]["RefractBench.app"]["files"][0], "0" * 64),
                ("product_bytes", payload["products"]["RefractBench.app"]["files"][0], None),
                ("executable", payload["products"]["RefractBench.app"]["files"][0], False),
        ):
            changed = copy.deepcopy(payload)
            if field == "source_sha256":
                changed["source_xctestrun"]["sha256"] = value
            else:
                entry = next(item for item in changed["products"]["RefractBench.app"]["files"]
                             if item["path"] == "RefractBench.app/RefractBench")
                if field == "product_sha256":
                    entry["sha256"] = value
                elif field == "product_bytes":
                    entry["bytes"] += 1
                else:
                    entry["executable"] = value
            self.replace_json(self.build_path, changed)
            with self.subTest(field=field), self.assertRaisesRegex(EvidenceError, "differs from the original"):
                make_report(self.manifest, self.root)
        changed = copy.deepcopy(payload)
        changed["products"]["RefractBench.app"]["directories"] = ["RefractBenchReference.app"]
        self.replace_json(self.build_path, changed)
        with self.assertRaisesRegex(EvidenceError, "differs from the original"):
            make_report(self.manifest, self.root)
        for directories in ([{}], ["RefractBench.app", 1], [None]):
            changed = copy.deepcopy(payload)
            changed["products"]["RefractBench.app"]["directories"] = directories
            self.replace_json(self.build_path, changed)
            with self.subTest(directories=directories), self.assertRaisesRegex(EvidenceError,
                                                                                "differs from the original"):
                make_report(self.manifest, self.root)
        self.manifest["environment"]["build_configuration"].pop("target")
        with self.assertRaisesRegex(EvidenceError, "explicit Release/iphonesimulator"):
            make_report(self.manifest, self.root)
        self.manifest["environment"]["build_configuration"]["target"] = "iphonesimulator"
        self.replace_json(self.build_path, payload)
        self.manifest["environment"]["target_label"] = "DEVICE"
        self.manifest["environment"]["device_result"] = True
        with self.assertRaisesRegex(EvidenceError, "producer and build destination"):
            make_report(self.manifest, self.root)

    def test_invalid_original_plist_is_an_evidence_error_not_parser_leak(self):
        path = self.derived_data / "Build/Products/Release-iphonesimulator/RefractBench.app/Info.plist"
        for payload in (b"<plist><dict><key>CFBundleExecutable</key>", b"not a plist"):
            path.write_bytes(payload)
            with self.subTest(payload=payload), self.assertRaisesRegex(EvidenceError, "Info.plist"):
                make_report(self.manifest, self.root)

    def test_raw_cadinterval_array_drives_p99_not_manifest_source_samples(self):
        measurement = next(entry for entry in self.manifest["measurements"] if entry["scenario"] == "scroll")
        path = next(path for path in measurement["artifacts"] if path.endswith("native-samples.json"))
        packet = self.timing_payload("generated", "scroll", 2)
        packet.update(frameIntervalMs=[1.0, 2.0, 3.0], iterationByFrame=[2, 2, 2])
        self.replace_json(path, packet)
        with self.assertRaisesRegex(EvidenceError, "raw native metric export"):
            make_report(self.manifest, self.root)
        measurement["value"] = 3.0
        report = make_report(self.manifest, self.root)
        sample = next(sample for sample in report["samples"] if sample["scenario"] == "scroll"
                      and sample["variant"] == "generated" and sample["iteration"] == 2)
        self.assertEqual(sample["source_samples"], [1.0, 2.0, 3.0])
        self.assertEqual(sample["value"], 3.0)

    def test_manifest_source_samples_cannot_replace_the_raw_display_array(self):
        self.manifest["measurements"][1]["source_samples"] = [10.0]
        with self.assertRaisesRegex(EvidenceError, "unknown fields"):
            make_report(self.manifest, self.root)

    def test_raw_memory_and_binary_values_must_match_declared_resources(self):
        for metric, path, value in (
                ("residentMemoryBytes", "raw/generated-scroll-2-memory.json", 999999),
                ("installedBinaryBytes", "raw/generated-startup-2-binary.json", 888888)):
            with self.subTest(metric=metric):
                manifest = copy.deepcopy(self.manifest)
                resource = next(entry for entry in manifest["resources"] if entry["metric"] == metric
                                and entry["variant"] == "generated")
                self.manifest["resources"] = manifest["resources"]
                payload = self.resource_payload("generated", resource["scenario"], resource["iteration"], metric)
                payload["bytes"] = value
                self.replace_json(path, payload)
                with self.assertRaisesRegex(EvidenceError, "resource bytes do not match"):
                    make_report(self.manifest, self.root)

    def test_raw_frame_revision_and_process_must_match_selected_iteration(self):
        measurement = next(entry for entry in self.manifest["measurements"] if entry["scenario"] == "scroll")
        path = next(path for path in measurement["artifacts"] if path.endswith("native-samples.json"))
        for key, value in (("sourceRevision", "b" * 40), ("pid", 9999), ("iterationByFrame", [2, 3])):
            packet = self.timing_payload("generated", "scroll", 2)
            packet[key] = value
            self.replace_json(path, packet)
            with self.subTest(key=key), self.assertRaisesRegex(EvidenceError, "identity|process|tags"):
                make_report(self.manifest, self.root)

    def test_raw_binary_identity_must_match_its_resource_artifact(self):
        path = "raw/generated-startup-2-binary.json"
        payload = self.resource_payload("generated", "startup", 2, "installedBinaryBytes")
        payload["sourceRevision"] = "b" * 40
        self.replace_json(path, payload)
        with self.assertRaisesRegex(EvidenceError, "identity"):
            make_report(self.manifest, self.root)

        payload = self.build_payload()
        payload["source_revision"] = "b" * 40
        self.replace_json(self.build_path, payload)
        with self.assertRaisesRegex(EvidenceError, "internal revision"):
            make_report(self.manifest, self.root)
        payload["source_revision"] = "a" * 40
        payload["products"].pop("RefractBench.app")
        self.replace_json(self.build_path, payload)
        with self.assertRaisesRegex(EvidenceError, "differs from the original"):
            make_report(self.manifest, self.root)

    def test_frame_reduction_uses_nearest_rank_and_preserves_thresholds(self):
        self.assertEqual(percentile([1.0, 8.0, 30.0], 0.99), 30.0)
        self.assertEqual(percentile([1.0, 8.0, 30.0], 0.5), 8.0)
        startup = [entry for entry in self.manifest["measurements"] if entry["scenario"] == "startup"]
        for entry in startup:
            self.set_startup_duration(entry, 20.0)
        for entry in startup:
            if entry["variant"] == "generated":
                self.set_startup_duration(entry, 20.6)
        self.set_startup_duration(next(entry for entry in reversed(startup) if entry["variant"] == "generated"), 40.0)
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
                self.set_startup_duration(entry, 10.06)
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
        other_artifact["scenario"] = "startup"
        self.replace_json(reference_binary["artifacts"][0], self.resource_payload("reference", "startup", 3,
                                                                                 "installedBinaryBytes"))
        self.manifest["resources"].append(other_iteration)
        with self.assertRaisesRegex(EvidenceError, "same iteration's build identity"):
            make_report(self.manifest, self.root)
        other_artifact["iteration"] = 2
        other_iteration["iteration"] = 2
        other_artifact["scenario"] = "scroll"
        other_iteration["scenario"] = "scroll"
        self.replace_json(reference_binary["artifacts"][0], self.resource_payload("reference", "scroll", 2,
                                                                                 "installedBinaryBytes"))
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

    def use_harmony_native_metrics(self):
        self.manifest["platform"] = "harmonyos"
        self.manifest["environment"]["platform"] = "harmonyos"
        self.use_harmony_build_provenance()
        for artifact in self.manifest["artifacts"]:
            artifact["kind"] = "vendor-metric-json" if artifact["kind"] != "xctrace" else "vendor-trace"
        for measurement in self.manifest["measurements"]:
            measurement["platform"] = "harmonyos"
            measurement["metric"] = "startupMs" if measurement["scenario"] == "startup" else "frameDurationMs"
            measurement["definition"] = ("native-launch-duration" if measurement["scenario"] == "startup"
                                         else "native-frame-duration")
            if measurement["scenario"] == "startup":
                measurement.update(native_pid=None)
            else:
                measurement["native_pid"] = 4242
        for resource in self.manifest["resources"]:
            resource["platform"] = "harmonyos"
            resource["native_pid"] = 4242 if resource["metric"] == "residentMemoryBytes" else None
        for artifact in self.manifest["artifacts"]:
            if artifact["role"] == "timing":
                measurement = next(entry for entry in self.manifest["measurements"]
                                   if (entry["variant"], entry["scenario"], entry["iteration"])
                                   == (artifact["variant"], artifact["scenario"], artifact["iteration"]))
                if artifact["scenario"] == "startup":
                    path = artifact["path"]
                    payload = self.timing_payload(artifact["variant"], "startup", artifact["iteration"])
                    payload = {key: value for key, value in payload.items()
                               if key not in ("nativeMeasurement", "nativeMeasurementSha256", "unit", "durationMs")}
                    payload.update(metric="native-launch-duration", timestampUnit="ms",
                                   launchStartTimestamp=90.0, firstFrameTimestamp=100.0)
                    self.replace_json(path, payload)
                else:
                    self.replace_json(artifact["path"], self.timing_payload(artifact["variant"], artifact["scenario"],
                                                                            artifact["iteration"]))

    def test_harmony_uses_vendor_native_metrics_with_explicit_scalar_definitions(self):
        self.use_harmony_native_metrics()
        report = make_report(self.manifest, self.root)
        self.assertEqual(report["platform"], "harmonyos")
        self.assertEqual(report["comparisons"][1]["metric"], "frameDurationMs")
        startup = next(entry for entry in self.manifest["measurements"] if entry["scenario"] == "startup")
        startup["launch_start_timestamp_ms"] = 80.0
        with self.assertRaisesRegex(EvidenceError, "unknown fields|timestamp"):
            make_report(self.manifest, self.root)

    def test_harmony_rejects_metric_selectors_instead_of_ignoring_them(self):
        self.use_harmony_native_metrics()
        for scenario in ("startup", "scroll"):
            measurement = next(entry for entry in self.manifest["measurements"] if entry["scenario"] == scenario)
            measurement["metric_selector"] = {"index": 99, "value_sha256": "0" * 64}
            with self.subTest(scenario=scenario), self.assertRaisesRegex(EvidenceError,
                                                                         "supported only for an iOS startup"):
                make_report(self.manifest, self.root)
            measurement.pop("metric_selector")
        self.assertEqual(make_report(self.manifest, self.root)["status"], "pass")
        startup = next(entry for entry in self.manifest["measurements"] if entry["scenario"] == "startup")
        startup["metric_selector"] = None
        with self.assertRaisesRegex(EvidenceError, "supported only for an iOS startup"):
            make_report(self.manifest, self.root)

    def test_harmony_needs_vendor_trace_not_an_ios_trace(self):
        self.manifest["platform"] = "harmonyos"
        self.manifest["environment"]["platform"] = "harmonyos"
        with self.assertRaisesRegex(EvidenceError, "not a native harmonyos artifact"):
            make_report(self.manifest, self.root)


if __name__ == "__main__":
    unittest.main()
