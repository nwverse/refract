#!/usr/bin/env python3
"""Export retained accepted iOS run directories as one schema-2 manifest.

This is an offline file transformation. It never invokes Xcode, Instruments, a
simulator or a device. Missing native timing, memory, binary or build evidence
fails before manifest.json is created; a partial staging directory is not a
reportable evidence set.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import stat
import sys
import xml.parsers.expat
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "common"))

from build_provenance import (BUNDLE_NAMES, BuildProvenanceError, bounded_file_bytes,
                              generated_test_runs, original_build_provenance)
from paired_report import (ITERATIONS, SCENARIOS, VARIANTS, EvidenceError, checked_frame_samples,
                           checked_iteration, checked_resource_value, checked_startup_value,
                           make_report, percentile, validate_environment)
from probe_target import find_simulator_targets


class ExportError(ValueError):
    pass


BUILD_NAME = "refract-build-provenance.json"
METRICS_PATH = "raw/metrics.json"
LEGACY_METRICS_PATH = "raw/exports/xctest-metrics.json"
MEMORY_PATH = "raw/exports/resident-memory.json"
BINARY_PATH = "raw/exports/installed-binary.json"
SUMMARY_PATH = "raw/exports/xctest-summary.json"
TESTS_PATH = "raw/exports/xctest-tests.json"
DERIVED_DATA_DESTINATION = "products/DerivedData"
CONFIGURATION_NAME_PATTERN = r"iteration-trace-config-[0-9a-f]{24}\.xctestrun"
JSON_DEPTH_LIMIT = 128
XCTEST_NODE_LIMIT = 4096


@dataclass(frozen=True)
class CopyJob:
    source: Path
    destination: str
    size: int
    sha256: str
    executable: bool = False


@dataclass(frozen=True)
class ExportPlan:
    manifest: dict[str, Any]
    jobs: tuple[CopyJob, ...]
    empty_directories: tuple[str, ...]


@dataclass(frozen=True)
class RunContext:
    revision: str
    build_sha256: str
    target: dict[str, Any]
    toolchain: dict[str, Any]
    selections: dict[tuple[str, int], dict[str, Any]]


def object_without_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ExportError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def bounded_json_containers(value: Any, depth: int = 1) -> None:
    """Bound direct callers as well as JSON decoded by the standard parser."""
    pending = [(value, depth)]
    while pending:
        current, level = pending.pop()
        if level > JSON_DEPTH_LIMIT:
            raise ExportError(f"Retained JSON exceeds its {JSON_DEPTH_LIMIT}-level nesting bound")
        if isinstance(current, dict):
            pending.extend((child, level + 1) for child in current.values())
        elif isinstance(current, list):
            pending.extend((child, level + 1) for child in current)


def read_json(path: Path) -> Any:
    try:
        data = bounded_file_bytes(path)
        value = json.loads(data, object_pairs_hook=object_without_duplicates,
                           parse_constant=lambda value: (_ for _ in ()).throw(
                               ExportError(f"Non-finite JSON value in {path.name}: {value}")))
    except (OSError, UnicodeError, json.JSONDecodeError, BuildProvenanceError, RecursionError) as error:
        raise ExportError(f"Cannot read retained JSON {path.name}: {error}") from error
    bounded_json_containers(value)
    return value


def read_object(path: Path) -> dict[str, Any]:
    value = read_json(path)
    if not isinstance(value, dict):
        raise ExportError(f"Retained JSON must be an object: {path.name}")
    return value


def real_directory(path: Path, label: str) -> Path:
    if not path.is_dir() or path.is_symlink():
        raise ExportError(f"{label} must be a real directory")
    return path


def real_build_directories(derived_data: Path) -> None:
    """Check every ancestor later used by the producer and the staged copy."""
    real_directory(derived_data, "Original DerivedData")
    for relative in ("Build", "Build/Products", "Build/Products/Release-iphonesimulator"):
        real_directory(derived_data / relative, f"Original DerivedData ancestor {relative}")


def bounded_text(value: Any, label: str, limit: int = 1024) -> str:
    if not isinstance(value, str) or not 0 < len(value) <= limit \
            or any(character in value for character in "\r\n\x00"):
        raise ExportError(f"{label} must be bounded single-line text")
    return value


def checked_sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
        raise ExportError(f"{label} requires a SHA-256 digest")
    return value


def safe_member(root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not 0 < len(relative) <= 4096 or "\\" in relative \
            or any(character in relative for character in "\r\n\x00"):
        raise ExportError("Retained paths must be bounded relative POSIX paths")
    parsed = PurePosixPath(relative)
    if parsed.is_absolute() or any(part in ("", ".", "..") for part in parsed.parts):
        raise ExportError(f"Unsafe retained path: {relative!r}")
    current = root
    for part in parsed.parts[:-1]:
        current = current / part
        try:
            mode = current.lstat().st_mode
        except OSError as error:
            raise ExportError(f"Missing retained directory: {relative}") from error
        if not stat.S_ISDIR(mode):
            raise ExportError(f"Retained path ancestors must be real directories: {relative}")
    return current / parsed.parts[-1]


def file_metadata(path: Path) -> tuple[int, str]:
    try:
        data = bounded_file_bytes(path)
    except (OSError, BuildProvenanceError) as error:
        raise ExportError(f"Invalid retained ordinary file {path.name}: {error}") from error
    return len(data), hashlib.sha256(data).hexdigest()


def require_fields(payload: dict[str, Any], expected: dict[str, Any], label: str) -> None:
    for key, value in expected.items():
        if type(payload.get(key)) is not type(value) or payload.get(key) != value:
            raise ExportError(f"{label} has a missing or mismatched {key}: {payload.get(key)!r}")


def verify_retained_files(run: Path) -> dict[str, Any]:
    accepted = read_object(run / "accepted-evidence.json")
    retained = read_object(run / "retained-file-hashes.json")
    files = retained.get("files")
    if retained.get("schema") != 1 or not isinstance(files, dict) or not files:
        raise ExportError("A retained-file manifest with ordinary file hashes is required")
    if accepted.get("retained_files") != {key: value for key, value in files.items()
                                          if key != "accepted-evidence.json"}:
        raise ExportError("Accepted evidence and retained-file inventory disagree")
    for relative, record in files.items():
        if not isinstance(record, dict) or set(record) != {"bytes", "sha256"}:
            raise ExportError(f"Malformed retained-file identity: {relative}")
        size, checksum = file_metadata(safe_member(run, relative))
        if type(record["bytes"]) is not int or record["bytes"] != size or record["sha256"] != checksum:
            raise ExportError(f"Retained-file checksum or size mismatch: {relative}")
    return accepted


def load_environment(path: Path) -> dict[str, Any]:
    payload = read_object(path)
    required = {"source_revision", "target_label", "device_result", "target", "toolchain", "commands"}
    if set(payload) != required:
        raise ExportError(f"Environment input requires exactly {sorted(required)}")
    if not isinstance(payload["source_revision"], str) or not re.fullmatch(r"[0-9a-f]{40}",
                                                                          payload["source_revision"]):
        raise ExportError("Environment input requires a complete source revision")
    if payload["target_label"] != "SIMULATOR" or payload["device_result"] is not False:
        raise ExportError("The existing iOS producer supports only labelled SIMULATOR evidence")
    target = payload["target"]
    if not isinstance(target, dict) or not {"udid", "model", "os_version", "architecture"} <= set(target) \
            or set(target) - {"udid", "name", "model", "os_version", "architecture"}:
        raise ExportError("Target input requires UDID, model, OS and architecture, with an optional name")
    for key, value in target.items():
        bounded_text(value, f"Target {key}")
    toolchain = payload["toolchain"]
    if not isinstance(toolchain, dict) or set(toolchain) != {"xcode"}:
        raise ExportError("Toolchain input requires exactly its retained xcode version")
    bounded_text(toolchain["xcode"], "Toolchain xcode")
    commands = payload["commands"]
    if not isinstance(commands, list) or not 0 < len(commands) <= 32:
        raise ExportError("Externally asserted commands must be a nonempty bounded list")
    for command in commands:
        bounded_text(command, "Externally asserted command", 4096)
    return payload


def load_selections(path: Path | None, revision: str, build_sha256: str) -> dict[tuple[str, int], dict[str, Any]]:
    if path is None:
        return {}
    payload = read_object(path)
    if set(payload) != {"schema", "source_revision", "build_provenance_sha256", "selections"} \
            or payload.get("schema") != 1 or payload.get("source_revision") != revision \
            or payload.get("build_provenance_sha256") != build_sha256 \
            or not isinstance(payload.get("selections"), list):
        raise ExportError("Startup selections must bind this exact source revision and build")
    result = {}
    fields = {"variant", "scenario", "iteration", "index", "value_sha256"}
    for entry in payload["selections"]:
        if not isinstance(entry, dict) or set(entry) != fields or entry.get("scenario") != "startup" \
                or entry.get("variant") not in VARIANTS:
            raise ExportError("Each startup selector needs an explicit identity, index and value SHA-256")
        iteration = checked_iteration(entry.get("iteration"), "Startup selector iteration")
        identity = (entry["variant"], iteration)
        if identity in result or type(entry["index"]) is not int or entry["index"] < 0 \
                or not isinstance(entry["value_sha256"], str) \
                or not re.fullmatch(r"[0-9a-f]{64}", entry["value_sha256"]):
            raise ExportError("Startup selectors must be unique and checksummed")
        result[identity] = {"index": entry["index"], "value_sha256": entry["value_sha256"]}
    return result


def canonical_build(derived_data: Path, revision: str) -> tuple[dict[str, Any], str]:
    real_build_directories(derived_data)
    try:
        original = original_build_provenance(derived_data, revision)
    except (OSError, TypeError, ValueError, KeyError) as error:
        raise ExportError(f"Cannot recompute original build provenance: {error}") from error
    manifest = read_object(derived_data / BUILD_NAME)
    if manifest != original:
        raise ExportError("Retained build manifest differs from its original xctestrun and products")
    _, checksum = file_metadata(derived_data / BUILD_NAME)
    return original, checksum


def source_job(run: Path, source_relative: str, destination: str, identity: tuple[str, str, int],
               kind: str, role: str, revision: str, build_sha256: str) -> tuple[CopyJob, dict[str, Any]]:
    source = safe_member(run, source_relative)
    size, checksum = file_metadata(source)
    if size == 0:
        raise ExportError(f"Native artifacts cannot be empty: {source_relative}")
    variant, scenario, iteration = identity
    entry = {"path": destination, "kind": kind, "role": role, "variant": variant,
             "scenario": scenario, "iteration": iteration, "bytes": size, "sha256": checksum,
             "source_revision": revision, "build_provenance_sha256": build_sha256}
    return CopyJob(source, destination, size, checksum), entry


def checked_archive(run: Path, accepted: dict[str, Any], key: str) -> tuple[str, int, str]:
    record = accepted.get(key)
    if not isinstance(record, dict) or set(record) != {"path", "bytes", "sha256"}:
        raise ExportError(f"Accepted evidence lacks its archived {key}")
    size, checksum = file_metadata(safe_member(run, record["path"]))
    if type(record["bytes"]) is not int or record["bytes"] != size or record["sha256"] != checksum:
        raise ExportError(f"Accepted {key} differs from its retained archive")
    return record["path"], size, checksum


def checked_file_reference(run: Path, record: Any, relative: str, label: str) -> str:
    if not isinstance(record, dict) or set(record) != {"path", "sha256"} \
            or record.get("path") != relative:
        raise ExportError(f"{label} must bind exactly {relative} and its SHA-256")
    checksum = checked_sha256(record.get("sha256"), label)
    if file_metadata(safe_member(run, relative))[1] != checksum:
        raise ExportError(f"{label} checksum does not match retained bytes")
    return checksum


def checked_native_packets(run: Path, result: dict[str, Any], identity: tuple[str, str, int],
                           revision: str, pid: int) -> dict[str, dict[str, str]]:
    variant, scenario, iteration = identity
    packets = {"native_process": "control/native-process.json", "request": "raw/request.json",
               "native_completion": "control/native-completion.json", "completion": "raw/completion.json"}
    references = {}
    for role, relative in packets.items():
        packet = read_object(safe_member(run, relative))
        expected = {"schema": 1, "session": result.get("session"), "revision": revision,
                    "variant": variant, "scenario": scenario, "iteration": iteration, "pid": pid,
                    "process": "running",
                    "state": "complete" if role.endswith("completion") else "ready"}
        require_fields(packet, expected, f"Startup {role}")
        for key, value in expected.items():
            if type(packet.get(key)) is not type(value):
                raise ExportError(f"Startup {role} has an incorrectly typed {key}")
        if role.endswith("completion") \
                and packet.get("completion") != f"{variant} {scenario} complete 1":
            raise ExportError(f"Startup {role} does not match this iteration")
        references[role] = {"path": relative, "sha256": file_metadata(safe_member(run, relative))[1]}
    return references


def checked_producer_startup(run: Path, result: dict[str, Any], identity: tuple[str, str, int],
                             revision: str, build_sha256: str, pid: int) -> tuple[dict[str, Any], dict[str, Any]]:
    raw = read_object(safe_member(run, METRICS_PATH))
    provenance = raw.get("provenance")
    if set(raw) != {"measurements", "metric_selector", "provenance"} \
            or not isinstance(provenance, dict) \
            or set(provenance) != {"native_test_identifier_url", "trace_receipt_sha256",
                                   "trace_configuration_receipt_sha256", "native_pid", "native_process_packets",
                                   "export_commands", "raw_exports"} \
            or provenance.get("native_pid") != pid or type(provenance.get("native_pid")) is not int:
        raise ExportError("Normalized startup metrics require complete native-PID provenance")
    expected = {key: value for key, value in (("path", "raw/iteration-trace.json"),
                                              ("sha256", provenance["trace_receipt_sha256"]))}
    checked_file_reference(run, expected, "raw/iteration-trace.json", "Startup trace receipt")
    expected = {key: value for key, value in (("path", "iteration-trace-config.json"),
                                              ("sha256", provenance["trace_configuration_receipt_sha256"]))}
    checked_file_reference(run, expected, "iteration-trace-config.json", "Startup configuration receipt")
    packets = checked_native_packets(run, result, identity, revision, pid)
    if provenance["native_process_packets"] != packets:
        raise ExportError("Normalized startup native-process packets differ from their retained identities")
    measurements = raw["measurements"]
    if not isinstance(measurements, list) or len(measurements) != 1 \
            or not isinstance(measurements[0], dict) \
            or measurements[0].get("pid") != pid or type(measurements[0].get("pid")) is not int:
        raise ExportError("Normalized startup metrics require exactly one exact positive native PID")
    measurement = measurements[0]
    identifier = f"RefractBenchUITests/test{identity[0].capitalize()}StartupTrace()"
    expected_url = ("test://com.apple.xcode/RefractBench/RefractBenchUITests/"
                    f"RefractBenchUITests/test{identity[0].capitalize()}StartupTrace")
    require_fields(measurement, {"nativeMetricIdentifier":
                                 "com.apple.dt.XCTMetric_ApplicationLaunch-AppLaunch.duration",
                                 "nativeTestIdentifier": identifier}, "Normalized startup metric")
    if provenance["native_test_identifier_url"] != expected_url:
        raise ExportError("Normalized startup selector URL does not match its exact XCTest")
    native_value = measurement.get("nativeValue")
    if not isinstance(native_value, dict) or set(native_value) != {"unitOfMeasurement", "measurements"} \
            or native_value["unitOfMeasurement"] not in ("s", "seconds") \
            or not isinstance(native_value["measurements"], list) \
            or len(native_value["measurements"]) != 1:
        raise ExportError("Normalized startup metrics require exactly one native second sample")
    exports = provenance["raw_exports"]
    if not isinstance(exports, dict) or set(exports) != {"xctest-tests.json", "xctest-metrics.json"}:
        raise ExportError("Normalized startup metrics require exact raw tests/metrics exports")
    for name, record in exports.items():
        checked_file_reference(run, record, f"raw/exports/{name}", f"Startup raw export {name}")
    commands = provenance["export_commands"]
    if not isinstance(commands, list) or len(commands) != 2:
        raise ExportError("Normalized startup metrics require both retained export commands")
    metric_command = next((command for command in commands if isinstance(command, list)
                           and "metrics" in command), None)
    if metric_command is None or metric_command[-2:] != ["--test-id", identifier] \
            or any(not isinstance(value, str) or any(character in value for character in "\r\n\x00")
                   for command in commands for value in command):
        raise ExportError("Normalized startup metrics lack their exact selector-bound export command")
    return raw, raw["metric_selector"]


def checked_resource_receipt(run: Path, result: dict[str, Any], identity: tuple[str, str, int],
                             metric: str, alias: str | None) -> None:
    record = result.get("native_resources")
    if not isinstance(record, dict) or set(record) != {"path", "sha256", "exports"}:
        raise ExportError("Iteration receipt lacks its native-resource identity")
    checked_file_reference(run, {"path": record["path"], "sha256": record["sha256"]},
                           "raw/native-resources.json", "Native resource packet")
    exports = record["exports"]
    if not isinstance(exports, dict) or set(exports) != {"residentMemoryBytes", "installedBinaryBytes"}:
        raise ExportError("Iteration receipt must retain both original native-resource exports")
    definitions = {"residentMemoryBytes": "task_info.TASK_VM_INFO.resident_size",
                   "installedBinaryBytes": "Bundle.main.regular-file-bytes"}
    original = "raw/native-memory.json" if metric == "residentMemoryBytes" else "raw/native-binary.json"
    for resource_metric, reference in exports.items():
        if not isinstance(reference, dict) or set(reference) != {"path", "sha256", "definition"} \
                or reference.get("definition") != definitions.get(resource_metric):
            raise ExportError("Native-resource export lacks its exact definition and retained identity")
        resource_original = "raw/native-memory.json" if resource_metric == "residentMemoryBytes" \
            else "raw/native-binary.json"
        original_checksum = file_metadata(safe_member(run, resource_original))[1]
        reference_checksum = checked_file_reference(
            run, {"path": reference.get("path"), "sha256": reference.get("sha256")},
            reference.get("path") if isinstance(reference.get("path"), str) else "",
            f"Native-resource {resource_metric} export")
        if original_checksum != reference_checksum \
                or file_metadata(safe_member(run, resource_original))[0] \
                != file_metadata(safe_member(run, reference["path"]))[0] \
                or bounded_file_bytes(safe_member(run, resource_original)) \
                != bounded_file_bytes(safe_member(run, reference["path"])):
            raise ExportError("Selected native-resource alias differs byte-for-byte from its original")
    expected_alias = alias if alias is not None else original
    if exports[metric]["path"] != expected_alias:
        raise ExportError(f"Native-resource {metric} must expose only its selected schema-2 alias")


def checked_resource_packet(run: Path, result: dict[str, Any], identity: tuple[str, str, int],
                            revision: str, pid: int, metric: str, alias: str | None) -> None:
    packet = read_json(safe_member(run, "raw/native-resources.json"))
    if not isinstance(packet, list) or len(packet) != 2:
        raise ExportError("The original native-resource packet must retain both snapshots")
    expected = {"schema": 1, "session": result.get("session"), "sourceRevision": revision,
                "variant": identity[0], "scenario": identity[1], "iteration": identity[2],
                "metric": metric, "unit": "bytes",
                "definition": "task_info.TASK_VM_INFO.resident_size"
                if metric == "residentMemoryBytes" else "Bundle.main.regular-file-bytes"}
    matches = [resource for resource in packet if isinstance(resource, dict)
               and resource.get("metric") == metric]
    if len(matches) != 1:
        raise ExportError("Native-resource packet must have unique memory and binary snapshots")
    require_fields(matches[0], expected, "Original native resource")
    if metric == "residentMemoryBytes" and matches[0].get("pid") != pid:
        raise ExportError("Original resident-memory packet has an unrelated native PID")
    checked_resource_receipt(run, result, identity, metric, alias)


def resource_bytes(run: Path, relative: str, identity: tuple[str, str, int], metric: str,
                   revision: str, pid: int | None) -> int:
    artifact = {"resolved_path": safe_member(run, relative), "path": relative,
                "variant": identity[0], "scenario": identity[1], "iteration": identity[2]}
    # The strict reader above rejects duplicate JSON keys before the reporter's
    # native-resource validator recomputes the byte value from the same file.
    read_object(artifact["resolved_path"])
    return checked_resource_value(artifact, metric, revision, pid)


def checked_configuration(run: Path, derived_data: Path, receipt: dict[str, Any], revision: str,
                          iteration: int, build_sha256: str, source_xctestrun: str) -> None:
    control = str(run.resolve(strict=True) / "control")
    expected = {"schema": 1, "source_revision": revision, "iteration": iteration,
                "control_directory": control, "build_provenance_sha256": build_sha256,
                "archive": "iteration-trace-config.xctestrun", "source_xctestrun": source_xctestrun}
    require_fields(receipt, expected, "Trace configuration")
    identity = hashlib.sha256(f"{revision}\0{control}\0{iteration}".encode()).hexdigest()[:24]
    name = f"iteration-trace-config-{identity}.xctestrun"
    if receipt.get("path") != name or not re.fullmatch(CONFIGURATION_NAME_PATTERN, name):
        raise ExportError("Trace configuration name is not the canonical revision/control/iteration identity")
    checksum = checked_sha256(receipt.get("configuration_sha256"), "Trace configuration")
    archived = safe_member(run, "iteration-trace-config.xctestrun")
    if file_metadata(archived)[1] != checksum:
        raise ExportError("Archived trace configuration differs from its receipt")
    destination = safe_member(derived_data, f"Build/Products/{name}")
    if file_metadata(destination)[1] != checksum:
        raise ExportError("Executed trace configuration differs from its retained archive")
    try:
        plist = plistlib.loads(bounded_file_bytes(archived))
    except (OSError, BuildProvenanceError, plistlib.InvalidFileException,
            xml.parsers.expat.ExpatError) as error:
        raise ExportError(f"Cannot read archived trace configuration: {error}") from error
    if not isinstance(plist, dict) or set(plist) != {"__xctestrun_metadata__", "RefractBenchUITests"}:
        raise ExportError("Archived trace configuration must contain exactly its metadata and hosted test")
    test = plist["RefractBenchUITests"]
    if not isinstance(test, dict) or not isinstance(test.get("TestingEnvironmentVariables"), dict):
        raise ExportError("Archived trace configuration lacks its hosted-test environment")
    environment = test["TestingEnvironmentVariables"]
    expected_environment = {"REFRACT_BENCH_REVISION": revision, "REFRACT_BENCH_TRACE_CONTROL": control,
                            "REFRACT_BENCH_TRACE_ITERATION": str(iteration)}
    for key, value in expected_environment.items():
        if environment.get(key) != value:
            raise ExportError(f"Archived hosted-test environment has a missing or mismatched {key}")


def normalized_os_version(value: Any) -> str:
    text = bounded_text(value, "XCTest device OS version", 128)
    return text[4:] if text.startswith("iOS ") else text


def device_identity(device: Any, label: str) -> dict[str, str]:
    if not isinstance(device, dict):
        raise ExportError(f"{label} device record must be an object")
    fields = {"deviceId": "udid", "deviceName": "name", "modelName": "model",
              "osVersion": "os_version", "architecture": "architecture"}
    identity = {}
    for key, output in fields.items():
        identity[output] = bounded_text(device.get(key), f"{label} device {key}", 128)
    identity["os_version"] = normalized_os_version(identity["os_version"])
    if device.get("platform") != "iOS Simulator":
        raise ExportError(f"{label} device is not explicitly an iOS Simulator")
    return identity


def checked_xctest_case(tests: dict[str, Any], identifier: str) -> dict[str, Any]:
    """Find one selector in XCTest's nested containers, not arbitrary JSON fields."""
    containers = tests.get("testNodes")
    if not isinstance(containers, list):
        raise ExportError("Normalized startup requires its exact passing XCTest case")
    pending = [(node, 1) for node in containers]
    matches = []
    visited = 0
    while pending:
        node, depth = pending.pop()
        visited += 1
        if visited > XCTEST_NODE_LIMIT or depth > JSON_DEPTH_LIMIT:
            raise ExportError("XCTest node traversal exceeds its bounded depth or node count")
        if not isinstance(node, dict):
            continue
        children = node.get("children", [])
        if not isinstance(children, list):
            raise ExportError("XCTest node children must be arrays")
        pending.extend((child, depth + 1) for child in children)
        # A test-case container is counted once; its child summaries are not
        # another execution of the same selector.
        if node.get("nodeType") == "Test Case" and node.get("nodeIdentifier") == identifier:
            matches.append(node)
    if len(matches) != 1:
        raise ExportError("Normalized startup requires its exact passing XCTest case")
    case = matches[0]
    if case.get("name") != identifier or case.get("result") != "Passed":
        raise ExportError("Normalized startup requires its exact passing XCTest case")
    return case


def checked_target_evidence(run: Path, accepted: dict[str, Any], target: dict[str, Any], *,
                            startup: bool = False) -> None:
    expected = {key: value for key, value in target.items() if key != "model"}
    summary_hash = checked_sha256(accepted.get("xctest_summary_sha256"), "Accepted summary export")
    tests_hash = checked_sha256(accepted.get("xctest_tests_sha256"), "Accepted tests export")
    summary_path = safe_member(run, SUMMARY_PATH)
    tests_path = safe_member(run, TESTS_PATH)
    if file_metadata(summary_path)[1] != summary_hash or file_metadata(tests_path)[1] != tests_hash:
        raise ExportError("Accepted XCTest target-export checksums do not match retained bytes")
    summary = read_object(summary_path)
    configurations = summary.get("devicesAndConfigurations")
    if not isinstance(configurations, list) or len(configurations) != 1 \
            or not isinstance(configurations[0], dict):
        raise ExportError("XCTest summary must retain exactly one device configuration")
    summary_device = device_identity(configurations[0].get("device"), "XCTest summary")
    require_fields(summary, {"result": "Passed", "passedTests": 1, "failedTests": 0, "skippedTests": 0},
                   "XCTest summary")
    tests = read_object(tests_path)
    if startup:
        raw = read_object(safe_member(run, METRICS_PATH))
        metrics = read_json(safe_member(run, LEGACY_METRICS_PATH))
        measurement = raw["measurements"][0]
        identifier = measurement["nativeTestIdentifier"]
        expected_url = raw["provenance"]["native_test_identifier_url"]
        checked_xctest_case(tests, identifier)
        if not isinstance(metrics, list) or len(metrics) != 1 or not isinstance(metrics[0], dict):
            raise ExportError("Normalized startup requires one exact-selector raw metrics export")
        runs = metrics[0].get("testRuns")
        if metrics[0].get("testIdentifier") != identifier \
                or metrics[0].get("testIdentifierURL", expected_url) != expected_url \
                or not isinstance(runs, list) or len(runs) != 1 or not isinstance(runs[0], dict):
            raise ExportError("Normalized startup raw metrics do not bind the exact selector")
        configurations = tests.get("testPlanConfigurations")
        if not isinstance(configurations, list) or len(configurations) != 1 \
                or runs[0].get("testPlanConfiguration") != configurations[0]:
            raise ExportError("Normalized startup test and metrics configurations differ")
        native_metrics = runs[0].get("metrics")
        if not isinstance(native_metrics, list) or len(native_metrics) != 1:
            raise ExportError("Normalized startup duration differs from its selector-bound raw metric")
        native_metric = native_metrics[0]
        # The producer's selector checksum covers the complete normalized
        # measurement. The raw export additionally carries presentation-only
        # metadata such as displayName; compare the identity, unit and exact
        # samples without stripping or rewriting the retained raw object.
        if not isinstance(native_metric, dict) \
                or native_metric.get("identifier") != measurement["nativeMetricIdentifier"] \
                or {key: native_metric.get(key) for key in ("unitOfMeasurement", "measurements")} \
                != measurement["nativeValue"]:
            raise ExportError("Normalized startup duration differs from its selector-bound raw metric")
        tests_device = device_identity(runs[0].get("device"), "XCTest selector metrics")
    else:
        devices = tests.get("devices")
        if not isinstance(devices, list) or len(devices) != 1:
            raise ExportError("XCTest tests must retain exactly one device record")
        tests_device = device_identity(devices[0], "XCTest tests")
    if summary_device != tests_device or any(summary_device[key] != value for key, value in expected.items()):
        raise ExportError("XCTest device records differ from the export environment")
    if "name" not in target and summary_device["name"] != accepted.get("target_name"):
        raise ExportError("XCTest device name differs from accepted evidence")

    probe = read_object(safe_member(run, "target.json"))
    require_fields(probe, {"target_label": "SIMULATOR", "device_result": False, "state": "Booted",
                           "udid": target["udid"], "model": target["model"]}, "Retained target probe")
    simulators = read_object(safe_member(run, "simulators.json"))
    simulator_devices = simulators.get("devices")
    if not isinstance(simulator_devices, dict):
        raise ExportError("Retained simulator probe requires a devices object")
    matches = [device for records in simulator_devices.values() if isinstance(records, list)
               for device in records if isinstance(device, dict) and device.get("udid") == target["udid"]]
    if len(matches) != 1 or any(matches[0].get(key) != value for key, value in (
            ("deviceTypeIdentifier", target["model"]), ("name", summary_device["name"]), ("state", "Booted"))):
        raise ExportError("Retained simulator probe does not bind the requested model, name and UDID")
    raw_targets = read_object(safe_member(run, "targets.json"))
    try:
        target_matches = find_simulator_targets(raw_targets, target["udid"])
    except (AttributeError, RecursionError) as error:
        raise ExportError("Malformed retained target probe") from error
    if len(target_matches) != 1:
        raise ExportError("Retained devicectl probe does not confirm one booted simulated target")
    hardware = target_matches[0].get("hardwareProperties")
    properties = target_matches[0].get("deviceProperties")
    if not isinstance(hardware, dict) or not isinstance(properties, dict) \
            or hardware.get("marketingName") != summary_device["model"] \
            or hardware.get("cpuType", {}).get("name") != summary_device["architecture"] \
            or properties.get("osVersionNumber") != summary_device["os_version"] \
            or properties.get("name") != summary_device["name"]:
        raise ExportError("Retained devicectl probe differs from the XCTest device records")


def load_run(run: Path, derived_data: Path, context: RunContext, source_xctestrun: str) -> tuple[
        list[CopyJob], list[dict[str, Any]], dict[str, Any], list[dict[str, Any]]]:
    real_directory(run, "Iteration run")
    receipt = read_object(run / "iteration-trace-config.json")
    result = read_object(run / "raw/iteration-trace.json")
    accepted = verify_retained_files(run)
    variant, scenario = result.get("variant"), result.get("scenario")
    if variant not in VARIANTS or scenario not in SCENARIOS:
        raise ExportError("Iteration receipt has an unsupported variant or scenario")
    iteration = checked_iteration(result.get("iteration"), "Retained iteration")
    identity = (variant, scenario, iteration)
    require_fields(receipt, {"schema": 1, "source_revision": context.revision, "iteration": iteration,
                             "control_directory": str(run.resolve(strict=True) / "control"),
                             "build_provenance_sha256": context.build_sha256}, "Trace configuration")
    archived_build = safe_member(run, BUILD_NAME)
    if file_metadata(archived_build)[1] != context.build_sha256:
        raise ExportError("An iteration cannot use a different build provenance manifest")
    checked_configuration(run, derived_data, receipt, context.revision, iteration, context.build_sha256,
                          source_xctestrun)
    require_fields(result, {"schema": 1, "status": "complete", "session": 1,
                            "source_revision": context.revision, "variant": variant, "scenario": scenario,
                            "iteration": iteration, "target_label": "SIMULATOR", "device_result": False,
                            "target_udid": context.target["udid"], "recorder": "xctrace",
                            "native_iteration_completion": f"{variant} {scenario} complete 1"},
                   "Iteration trace")
    require_fields(accepted, {"schema": 1, "status": "accepted-native-iteration",
                              "source_revision": context.revision, "variant": variant, "scenario": scenario,
                              "iteration": iteration, "target_label": "SIMULATOR", "device_result": False,
                              "target_udid": context.target["udid"], "recorder_exit": 0,
                              "test_counts": {"passed": 1, "failed": 0, "skipped": 0}}, "Accepted evidence")
    pid = result.get("pid")
    if type(pid) is not int or pid <= 0 or accepted.get("native_pid") != pid:
        raise ExportError("Iteration and accepted evidence must retain one positive native PID")
    if accepted.get("target_os_version") not in {context.target["os_version"], "iOS " + context.target["os_version"]} \
            or accepted.get("xcode_version") != context.toolchain["xcode"] \
            or ("name" in context.target and accepted.get("target_name") != context.target["name"]):
        raise ExportError("Accepted target or toolchain differs from the export environment")
    normalized_metrics = os.path.lexists(safe_member(run, METRICS_PATH))
    checked_target_evidence(run, accepted, context.target,
                            startup=scenario == "startup" and normalized_metrics)

    prefix = f"raw/{variant}-{scenario}-{iteration}"
    trace_source, trace_size, trace_hash = checked_archive(run, accepted, "trace_zip")
    if (result.get("trace") != trace_source or result.get("bytes") != trace_size
            or result.get("sha256") != trace_hash
            or result.get("archived_package_name") != f"{variant}-{scenario}-{iteration}.trace"):
        raise ExportError("Profiler receipt and accepted archive disagree")
    result_source, _, _ = checked_archive(run, accepted, "xcresult_zip")
    jobs, artifacts = [], []
    for source, destination, kind, role in (
            (trace_source, prefix + "-profiler.trace.zip", "xctrace", "profiler"),
            (result_source, prefix + "-results.xcresult.zip", "xcresult", "timing")):
        job, entry = source_job(run, source, destination, identity, kind, role,
                                context.revision, context.build_sha256)
        jobs.append(job)
        artifacts.append(entry)

    measurement = {"platform": "ios", "variant": variant, "scenario": scenario, "iteration": iteration,
                   "unit": "ms", "artifacts": []}
    resources = []
    if scenario == "startup":
        if normalized_metrics:
            raw, selector = checked_producer_startup(run, result, identity, context.revision,
                                                     context.build_sha256, pid)
            supplied_selector = context.selections.get((variant, iteration))
            if supplied_selector is not None and supplied_selector != selector:
                raise ExportError("An external startup selector cannot override normalized embedded selection")
            timing_source = METRICS_PATH
            if os.path.lexists(safe_member(run, LEGACY_METRICS_PATH)):
                # The producer's exact-selector raw array remains retained for
                # provenance; it is not an interchangeable normalized scalar.
                legacy = read_json(safe_member(run, LEGACY_METRICS_PATH))
                if isinstance(legacy, dict) and ("measurements" in legacy or "nativeMeasurement" in legacy):
                    raise ExportError("Legacy normalized and producer-shaped startup inputs are mutually exclusive")
        else:
            # Explicit compatibility for older already-accepted runs. New
            # producer-shaped runs never fall back to the historical raw array.
            timing_source = LEGACY_METRICS_PATH
            raw = read_object(safe_member(run, timing_source))
            if accepted.get("xctest_metrics_sha256") != file_metadata(safe_member(run, timing_source))[1]:
                raise ExportError("Accepted startup metric export checksum does not match")
            selector = context.selections.get((variant, iteration))
        if "firstDisplay" in raw or "timestamp" in raw:
            raise ExportError("A firstDisplay timestamp is not an application launch duration")
        value = checked_startup_value(raw, identity, context.revision, selector)
        measurement.update(metric="startupMs", value=value, definition="XCTApplicationLaunchMetric")
        if selector is not None:
            measurement["metric_selector"] = selector
        timing_destination = prefix + "-metrics.json"
    else:
        raw = read_object(safe_member(run, "raw/native-samples.json"))
        expected_keys = {"schema", "session", "sourceRevision", "variant", "scenario", "iteration", "pid",
                         "completedIterations", "recordedIteration", "frameIntervalMs", "iterationByFrame"}
        if set(raw) != expected_keys or accepted.get("native_samples_sha256") != file_metadata(
                safe_member(run, "raw/native-samples.json"))[1]:
            raise ExportError("Accepted native sample packet is missing or has an ambiguous schema")
        if result.get("native_samples") != {"path": "raw/native-samples.json",
                                            "sha256": accepted["native_samples_sha256"]}:
            raise ExportError("Iteration receipt does not bind the retained native sample packet")
        if raw.get("session") != result.get("session"):
            raise ExportError("Native sample session differs from the iteration receipt")
        intervals = checked_frame_samples(raw, identity, context.revision, pid, platform="ios")
        measurement.update(metric="frameIntervalMs", value=percentile(intervals, 0.99),
                           definition="CADisplayLink.targetTimestamp-timestamp", aggregation="p99", native_pid=pid)
        timing_source = "raw/native-samples.json"
        timing_destination = prefix + "-native-samples.json"
        memory_job, memory_artifact = source_job(
            run, MEMORY_PATH, prefix + "-memory.json", identity, "xcode-metric-json", "memory",
            context.revision, context.build_sha256)
        jobs.append(memory_job)
        artifacts.append(memory_artifact)
        memory_value = resource_bytes(run, MEMORY_PATH, identity, "residentMemoryBytes", context.revision, pid)
        resources.append({"platform": "ios", "variant": variant, "scenario": scenario, "iteration": iteration,
                          "metric": "residentMemoryBytes", "bytes": memory_value, "native_pid": pid,
                          "artifacts": [memory_artifact["path"]]})
    binary_exists = os.path.lexists(safe_member(run, BINARY_PATH))
    if identity == (variant, "startup", 2) and not binary_exists:
        raise ExportError(f"Missing installed binary evidence for {variant}; no partial manifest is emitted")
    if binary_exists:
        if identity != (variant, "startup", 2):
            raise ExportError("Installed binary evidence belongs only to the single startup/2 build pair")
        binary_job, binary_artifact = source_job(
            run, BINARY_PATH, f"raw/{variant}-startup-2-binary.json", identity,
            "xcode-metric-json", "binary", context.revision, context.build_sha256)
        jobs.append(binary_job)
        artifacts.append(binary_artifact)
        binary_value = resource_bytes(run, BINARY_PATH, identity, "installedBinaryBytes", context.revision, None)
        resources.append({"platform": "ios", "variant": variant, "scenario": "startup", "iteration": 2,
                          "metric": "installedBinaryBytes", "bytes": binary_value, "native_pid": None,
                          "artifacts": [binary_artifact["path"]]})
    timing_job, timing_artifact = source_job(run, timing_source, timing_destination, identity,
                                             "xcode-metric-json", "timing", context.revision,
                                             context.build_sha256)
    jobs.append(timing_job)
    artifacts.append(timing_artifact)
    measurement["artifacts"] = sorted([timing_artifact["path"], artifacts[0]["path"]])
    if os.path.lexists(safe_member(run, METRICS_PATH)) and scenario != "startup":
        raise ExportError("Normalized launch metrics belong only to startup")
    if os.path.lexists(safe_member(run, LEGACY_METRICS_PATH)) and scenario != "startup":
        raise ExportError("Launch metric exports belong only to startup")
    if os.path.lexists(safe_member(run, MEMORY_PATH)):
        if scenario == "startup":
            raise ExportError("Startup cannot supply a frame-iteration resident-memory measurement")
        checked_resource_packet(run, result, identity, context.revision, pid, "residentMemoryBytes", MEMORY_PATH)
    if scenario == "startup":
        alias = BINARY_PATH if identity == (variant, "startup", 2) else None
        checked_resource_packet(run, result, identity, context.revision, pid, "installedBinaryBytes", alias)
    return jobs, artifacts, measurement, resources


def discover_runs(roots: list[Path]) -> list[Path]:
    runs = []
    visited = 0
    for root in roots:
        real_directory(root, "Run root")
        root = root.resolve(strict=True)
        for directory, names, _ in os.walk(root, followlinks=False):
            current = Path(directory)
            visited += 1
            if visited > 4096:
                raise ExportError("Run discovery exceeds its 4096-directory bound")
            names.sort()
            if (current / "raw/iteration-trace.json").is_file():
                runs.append(current)
                names.clear()
                continue
            for name in names:
                if (current / name).is_symlink():
                    raise ExportError("Run discovery does not follow symbolic-link directories")
    return runs


def plan_export(run_roots: list[Path], derived_data: Path, environment_path: Path,
                selections_path: Path | None = None) -> ExportPlan:
    environment_input = load_environment(environment_path)
    revision = environment_input["source_revision"]
    build, build_sha256 = canonical_build(derived_data, revision)
    context = RunContext(revision, build_sha256, environment_input["target"], environment_input["toolchain"],
                         load_selections(selections_path, revision, build_sha256))
    expected = [(variant, scenario, iteration) for variant in VARIANTS for scenario in SCENARIOS
                for iteration in ITERATIONS]
    loaded = {}
    consumed_selectors = set()
    for run in discover_runs(run_roots):
        result = read_object(run / "raw/iteration-trace.json")
        identity = (result.get("variant"), result.get("scenario"), result.get("iteration"))
        if identity in loaded:
            raise ExportError(f"Duplicate retained iteration pair member: {identity}")
        loaded[identity] = load_run(run, derived_data, context, build["source_xctestrun"]["path"])
        if identity[1] == "startup" and (identity[0], identity[2]) in context.selections:
            consumed_selectors.add((identity[0], identity[2]))
    if consumed_selectors != set(context.selections):
        raise ExportError("A startup selector does not belong to any retained startup identity")
    missing = [identity for identity in expected if identity not in loaded]
    extra = [identity for identity in loaded if identity not in expected]
    if missing or extra:
        raise ExportError(f"Retained runs must contain exactly 2...30 for every pair; missing={missing}, extra={extra}")

    jobs = [CopyJob(derived_data / BUILD_NAME, "raw/refract-build-provenance.json",
                    *file_metadata(derived_data / BUILD_NAME))]
    artifacts = [{"path": "raw/refract-build-provenance.json", "kind": "xcresult", "role": "build-provenance",
                  "variant": "shared", "scenario": "build", "iteration": 2, "bytes": jobs[0].size,
                  "sha256": jobs[0].sha256, "source_revision": revision,
                  "build_provenance_sha256": build_sha256}]
    measurements, resources = [], []
    for identity in expected:
        run_jobs, run_artifacts, measurement, run_resources = loaded[identity]
        jobs.extend(run_jobs)
        artifacts.extend(run_artifacts)
        measurements.append(measurement)
        resources.extend(run_resources)
    environment = {"platform": "ios", **environment_input,
                   # The exporter verifies retained acquisition inputs and its
                   # deterministic copy, not caller-authored shell history.
                   "commands": ["offline-export-iteration-manifest"],
                   "export_command_template": "python3 -I bench/ios/export_iteration_manifest.py "
                                              "--run-root <retained-runs-root> "
                                              "--derived-data <original-DerivedData> "
                                              "--environment <export-environment.json> "
                                              "--output <previously-absent-evidence-directory>",
                   "externally_asserted_commands": environment_input["commands"],
                   "command_provenance": {
                       "commands": "verified offline export operation, not reconstructed acquisition commands",
                       "export_command_template": "documentation template for rerunning this exporter with "
                                                  "explicit caller-supplied paths; not recovered execution history",
                       "externally_asserted_commands": "caller-supplied acquisition assertions; "
                                                       "not reconstructed or evidence-verified by this exporter"},
                   "build_provenance": {"path": "raw/refract-build-provenance.json", "sha256": build_sha256},
                   "build_configuration": {"name": "Release", "target": "iphonesimulator",
                                           "derived_data": DERIVED_DATA_DESTINATION}}
    validate_environment(environment, "ios")
    manifest = {"schema": 2, "platform": "ios", "environment": environment,
                "artifacts": artifacts, "measurements": measurements, "resources": resources}

    for relative in ("Build/Products", "Build/Products/Release-iphonesimulator",
                     *(f"Build/Products/Release-iphonesimulator/{name}" for name in BUNDLE_NAMES)):
        real_directory(derived_data / relative, f"Original product ancestor {relative}")
    products = derived_data / "Build/Products"
    staged_products = Path(DERIVED_DATA_DESTINATION) / "Build/Products"
    source = generated_test_runs(derived_data)[0]
    jobs.append(CopyJob(source, (staged_products / source.name).as_posix(),
                        *file_metadata(source)))
    release = products / "Release-iphonesimulator"
    staged_release = staged_products / "Release-iphonesimulator"
    empty_directories = []
    for name in BUNDLE_NAMES:
        product = build["products"][name]
        # The nested test bundle also appears in its runner's complete file
        # inventory. Stage each canonical file once, then the reporter's
        # recomputed nested identity must still match every listed record.
        empty_directories.extend((staged_release / relative).as_posix() for relative in product["directories"])
        for entry in product["files"]:
            relative = entry["path"]
            source = release / relative
            jobs.append(CopyJob(source, (staged_release / relative).as_posix(),
                                *file_metadata(source), entry["executable"]))
    seen = set()
    unique_jobs = []
    for job in jobs:
        if job.destination in seen:
            if job.size == 0 or job.executable != (bool(job.source.stat().st_mode & 0o111)):
                raise ExportError(f"Conflicting duplicate product identity: {job.destination}")
            continue
        seen.add(job.destination)
        unique_jobs.append(job)
    return ExportPlan(manifest, tuple(unique_jobs), tuple(empty_directories))


def write_copy(output: Path, job: CopyJob) -> None:
    destination = output / job.destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    data = bounded_file_bytes(job.source)
    if len(data) != job.size or hashlib.sha256(data).hexdigest() != job.sha256:
        raise ExportError(f"Source changed during offline export: {job.source.name}")
    try:
        with destination.open("xb") as stream:
            stream.write(data)
        destination.chmod(0o755 if job.executable else 0o644)
    except FileExistsError as error:
        raise ExportError(f"Refusing to replace an existing export file: {job.destination}") from error
    if file_metadata(destination) != (job.size, job.sha256):
        raise ExportError(f"Exported checksum differs from retained evidence: {job.destination}")


def export_manifest(run_roots: list[Path], derived_data: Path, environment_path: Path,
                    output: Path, selections_path: Path | None = None) -> dict[str, Any]:
    if os.path.lexists(output):
        raise ExportError("Refusing to replace an existing evidence output")
    plan = plan_export(run_roots, derived_data, environment_path, selections_path)
    if os.path.lexists(output):
        raise ExportError("Refusing to replace an existing evidence output")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.mkdir()
    (output / "raw").mkdir()
    for relative in plan.empty_directories:
        (output / relative).mkdir(parents=True, exist_ok=True)
    for job in plan.jobs:
        write_copy(output, job)
    # Validate all staged bytes and the original-product identity before the
    # only manifest write. A regression report may have status=fail; that does
    # not make an otherwise complete manifest unwritable, and no report is emitted.
    make_report(plan.manifest, output)
    manifest_path = output / "manifest.json"
    with manifest_path.open("xb") as stream:
        stream.write((json.dumps(plan.manifest, indent=2, sort_keys=True, allow_nan=False) + "\n").encode())
    return plan.manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-root", required=True, action="append", type=Path,
                        help="A run directory or a directory tree containing retained runs; repeatable")
    parser.add_argument("--derived-data", required=True, type=Path, help="The original retained DerivedData")
    parser.add_argument("--environment", required=True, type=Path, help="Revision/target/toolchain/commands JSON")
    parser.add_argument("--startup-selections", type=Path,
                        help="Optional revision/build-bound selector JSON for native startup arrays")
    parser.add_argument("--output", required=True, type=Path, help="A previously absent evidence directory")
    args = parser.parse_args(argv)
    try:
        manifest = export_manifest(args.run_root, args.derived_data, args.environment, args.output,
                                   args.startup_selections)
    except (ExportError, EvidenceError, BuildProvenanceError, OSError, UnicodeError,
            json.JSONDecodeError, TypeError, ValueError, KeyError) as error:
        print(f"iteration-manifest-export: ERROR: {error}; no complete manifest was written", file=sys.stderr)
        return 2
    print(f"manifest={args.output / 'manifest.json'}\nmeasurements={len(manifest['measurements'])}\n"
          f"resources={len(manifest['resources'])}\nartifacts={len(manifest['artifacts'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
