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
import re
import stat
import sys
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


class ExportError(ValueError):
    pass


BUILD_NAME = "refract-build-provenance.json"
METRICS_PATH = "raw/exports/xctest-metrics.json"
MEMORY_PATH = "raw/exports/resident-memory.json"
BINARY_PATH = "raw/exports/installed-binary.json"
DERIVED_DATA_DESTINATION = "products/DerivedData"


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


def read_json(path: Path) -> Any:
    try:
        data = bounded_file_bytes(path)
        return json.loads(data, object_pairs_hook=object_without_duplicates,
                          parse_constant=lambda value: (_ for _ in ()).throw(
                              ExportError(f"Non-finite JSON value in {path.name}: {value}")))
    except (OSError, UnicodeError, json.JSONDecodeError, BuildProvenanceError) as error:
        raise ExportError(f"Cannot read retained JSON {path.name}: {error}") from error


def read_object(path: Path) -> dict[str, Any]:
    value = read_json(path)
    if not isinstance(value, dict):
        raise ExportError(f"Retained JSON must be an object: {path.name}")
    return value


def real_directory(path: Path, label: str) -> Path:
    if not path.is_dir() or path.is_symlink():
        raise ExportError(f"{label} must be a real directory")
    return path


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
        if not isinstance(value, str) or not value or any(character in value for character in "\r\n\x00"):
            raise ExportError(f"Target {key} must be bounded text")
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
    real_directory(derived_data, "Original DerivedData")
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


def resource_bytes(run: Path, relative: str, identity: tuple[str, str, int], metric: str,
                   revision: str, pid: int | None) -> int:
    artifact = {"resolved_path": safe_member(run, relative), "path": relative,
                "variant": identity[0], "scenario": identity[1], "iteration": identity[2]}
    # The strict reader above rejects duplicate JSON keys before the reporter's
    # native-resource validator recomputes the byte value from the same file.
    read_object(artifact["resolved_path"])
    return checked_resource_value(artifact, metric, revision, pid)


def load_run(run: Path, context: RunContext) -> tuple[list[CopyJob], list[dict[str, Any]], dict[str, Any],
                                                    list[dict[str, Any]]]:
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
    if accepted.get("target_os_version") != context.target["os_version"] \
            or accepted.get("xcode_version") != context.toolchain.get("xcode") \
            or ("name" in context.target and accepted.get("target_name") != context.target["name"]):
        raise ExportError("Accepted target or toolchain differs from the export environment")

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
        raw = read_object(safe_member(run, METRICS_PATH))
        if accepted.get("xctest_metrics_sha256") != file_metadata(safe_member(run, METRICS_PATH))[1]:
            raise ExportError("Accepted startup metric export checksum does not match")
        selector = context.selections.get((variant, iteration))
        if "firstDisplay" in raw or "timestamp" in raw:
            raise ExportError("A firstDisplay timestamp is not an application launch duration")
        value = checked_startup_value(raw, identity, context.revision, selector)
        measurement.update(metric="startupMs", value=value, definition="XCTApplicationLaunchMetric")
        if selector is not None:
            measurement["metric_selector"] = selector
        timing_source = METRICS_PATH
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
        intervals = checked_frame_samples(raw, identity, context.revision, pid)
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
    if os.path.lexists(safe_member(run, MEMORY_PATH)) and scenario == "startup":
        raise ExportError("Startup cannot supply a frame-iteration resident-memory measurement")
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
        loaded[identity] = load_run(run, context)
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
                   "build_provenance": {"path": "raw/refract-build-provenance.json", "sha256": build_sha256},
                   "build_configuration": {"name": "Release", "target": "iphonesimulator",
                                           "derived_data": DERIVED_DATA_DESTINATION}}
    validate_environment(environment, "ios")
    manifest = {"schema": 2, "platform": "ios", "environment": environment,
                "artifacts": artifacts, "measurements": measurements, "resources": resources}

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
            json.JSONDecodeError, TypeError, KeyError) as error:
        print(f"iteration-manifest-export: ERROR: {error}; no complete manifest was written", file=sys.stderr)
        return 2
    print(f"manifest={args.output / 'manifest.json'}\nmeasurements={len(manifest['measurements'])}\n"
          f"resources={len(manifest['resources'])}\nartifacts={len(manifest['artifacts'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
