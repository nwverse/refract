#!/usr/bin/env python3
"""Finalize already-acquired iOS evidence without changing any producer bytes.

The runner's receipt precedes normalized startup export. Its one-way hash into
that export is retained; the acceptance record binds both without adding a
reverse hash to the receipt. This tool never invokes a native toolchain.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import sys
from pathlib import Path

from export_iteration_manifest import (BINARY_PATH, MEMORY_PATH, PRODUCER_BINDING, PUBLICATION_NAMES,
                                       ExportError, canonical_build, checked_native_packets,
                                       checked_producer_binding, checked_producer_startup,
                                       checked_resource_packet, checked_target_evidence, file_metadata,
                                       load_environment, read_object, require_fields, verify_retained_files)
from paired_report import EvidenceError, checked_frame_samples, checked_iteration, checked_resource_value


def file_identity(path: Path) -> dict[str, object]:
    size, checksum = file_metadata(path)
    return {"bytes": size, "sha256": checksum}


def file_reference(path: Path, relative: str) -> dict[str, str]:
    return {"path": relative, "sha256": file_identity(path)["sha256"]}


def write_once(path: Path, payload: dict) -> None:
    with path.open("x", encoding="utf-8") as stream:
        json.dump(payload, stream, sort_keys=True, indent=2, allow_nan=False)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())


def retained_inventory(run: Path) -> dict[str, dict[str, object]]:
    files = {}
    for root, directories, names in os.walk(run, followlinks=False):
        directories.sort()
        for name in sorted(names):
            path = Path(root) / name
            relative = path.relative_to(run).as_posix()
            if path.is_symlink() or not path.is_file() or relative in PUBLICATION_NAMES:
                raise ExportError("Finalization requires ordinary producer files and no previous publication")
            if relative.startswith(".evidence-publication-") or relative in {
                    ".accepted-evidence.json.staging", ".retained-file-hashes.json.staging"}:
                raise ExportError("Finalization cannot retain an open staging file")
            files[relative] = file_identity(path)
    if not files:
        raise ExportError("No retained producer evidence is available")
    return files


def finalizer_metadata(metadata: Path, result: dict) -> dict:
    payload = read_object(metadata)
    if set(payload) != {"target", "toolchain", "commands"}:
        raise ExportError("Finalizer metadata requires exactly target, toolchain and commands")
    target = payload.get("target")
    if not isinstance(target, dict):
        raise ExportError("Finalizer target must be an object")
    require_fields(target, {"udid": result["target_udid"]}, "Finalizer target")
    return payload


def build_acceptance(run: Path, derived_data: Path, metadata: Path) -> tuple[dict, dict]:
    result = read_object(run / "raw/iteration-trace.json")
    configuration = read_object(run / "iteration-trace-config.json")
    variant, scenario, iteration = result.get("variant"), result.get("scenario"), result.get("iteration")
    identity = (variant, scenario, iteration)
    checked_iteration(iteration, "Finalized iteration")
    require_fields(result, {"schema": 1, "status": "complete", "source_revision": result.get("source_revision"),
                            "target_label": "SIMULATOR", "device_result": False}, "Finalized iteration")
    if not isinstance(result["source_revision"], str):
        raise ExportError("Finalization requires an exact source revision")
    metadata_payload = finalizer_metadata(metadata, result)
    build, build_hash = canonical_build(derived_data, result["source_revision"])
    require_fields(configuration, {"source_revision": result["source_revision"], "iteration": iteration,
                                   "build_provenance_sha256": build_hash}, "Finalized configuration")
    # The caller supplies acquisition-time target/toolchain observations; the
    # common reader below cross-checks them against retained XCTest/probe bytes.
    environment = {"source_revision": result["source_revision"], "target_label": "SIMULATOR",
                   "device_result": False, **metadata_payload}
    temporary_environment = derived_data / ".finalizer-environment.json"
    if os.path.lexists(temporary_environment):
        raise ExportError("Refusing to replace a finalizer environment input")
    try:
        write_once(temporary_environment, environment)
        environment = load_environment(temporary_environment)
    finally:
        temporary_environment.unlink(missing_ok=True)
    summary = read_object(run / "raw/exports/xctest-summary.json")
    require_fields(summary, {"result": "Passed", "passedTests": 1, "failedTests": 0, "skippedTests": 0},
                   "Finalized XCTest summary")
    pid = result.get("pid")
    if type(pid) is not int or pid <= 0:
        raise ExportError("Finalization requires one positive native PID")
    checked_native_packets(run, result, identity, result["source_revision"], pid)
    recorder = read_object(run / "raw/recorder-finished.json")
    require_fields(recorder, {"schema": result.get("schema"), "session": result.get("session"),
                              "revision": result.get("source_revision"), "variant": variant,
                              "scenario": scenario, "iteration": iteration, "pid": pid,
                              "state": "recorder-finished", "recorder_exit": 0},
                   "Finalized recorder")
    trace_path = run / result.get("trace", "")
    if not trace_path.is_file() or trace_path.is_symlink():
        raise ExportError("Finalization requires the retained profiler archive")
    resources = result.get("native_resources", {})
    aliases = resources.get("exports", {})
    if not isinstance(aliases, dict):
        raise ExportError("Finalization requires exact selected resource aliases")
    binding = {
        "protocol": PRODUCER_BINDING,
        "receipt": file_reference(run / "raw/iteration-trace.json", "raw/iteration-trace.json"),
        "configuration": file_reference(run / "iteration-trace-config.json", "iteration-trace-config.json"),
        "resources": {
            "original": file_reference(run / "raw/native-resources.json", "raw/native-resources.json"),
            "memory": file_reference(run / "raw/native-memory.json", "raw/native-memory.json"),
            "binary": file_reference(run / "raw/native-binary.json", "raw/native-binary.json"),
            "aliases": {metric: {"path": aliases[metric]["path"], "sha256": aliases[metric]["sha256"]}
                        for metric in ("residentMemoryBytes", "installedBinaryBytes")},
        },
    }
    if scenario == "startup":
        binding["normalized_metrics"] = file_reference(run / "raw/metrics.json", "raw/metrics.json")
        binding["native_process_packets"] = checked_producer_startup(
            run, result, identity, result["source_revision"], build_hash, pid)[0]["provenance"][
                "native_process_packets"]
    else:
        samples = read_object(run / "raw/native-samples.json")
        checked_frame_samples(samples, identity, result["source_revision"], pid, platform="ios")
        memory_alias = aliases["residentMemoryBytes"]["path"]
        checked_resource_value({"resolved_path": run / memory_alias, "path": memory_alias,
                                "variant": variant, "scenario": scenario, "iteration": iteration},
                               "residentMemoryBytes", result["source_revision"], pid)
    retained = retained_inventory(run)
    accepted = {
        "schema": 1, "status": "accepted-native-iteration", "source_revision": result["source_revision"],
        "variant": variant, "scenario": scenario, "iteration": iteration, "native_pid": pid,
        "target_label": "SIMULATOR", "device_result": False, "target_udid": result["target_udid"],
        "target_name": environment["target"]["name"],
        "target_os_version": environment["target"]["os_version"],
        "xcode_version": environment["toolchain"]["xcode"], "recorder_exit": 0,
        "test_counts": {"passed": 1, "failed": 0, "skipped": 0},
        "xctest_summary_sha256": file_identity(run / "raw/exports/xctest-summary.json")["sha256"],
        "xctest_tests_sha256": file_identity(run / "raw/exports/xctest-tests.json")["sha256"],
        "trace_zip": {"path": result["trace"], **file_identity(trace_path)},
        "xcresult_zip": {"path": "raw/results.xcresult.zip", **file_identity(run / "raw/results.xcresult.zip")},
        "retained_files": retained, "producer_binding": binding,
    }
    if scenario == "startup":
        accepted["xctest_metrics_sha256"] = file_identity(run / "raw/exports/xctest-metrics.json")["sha256"]
        accepted["normalized_metrics_sha256"] = file_identity(run / "raw/metrics.json")["sha256"]
        checked_resource_packet(run, result, identity, result["source_revision"], pid, "installedBinaryBytes",
                                BINARY_PATH if iteration == 2 else None)
    else:
        accepted["native_samples_sha256"] = file_identity(run / "raw/native-samples.json")["sha256"]
        checked_resource_packet(run, result, identity, result["source_revision"], pid, "residentMemoryBytes",
                                MEMORY_PATH)
    return accepted, environment


def finalize_iteration(run: Path, derived_data: Path, metadata: Path) -> dict:
    if not run.is_dir() or run.is_symlink():
        raise ExportError("Finalization requires a real retained run directory")
    for name in PUBLICATION_NAMES:
        if os.path.lexists(run / name):
            raise ExportError(f"Refusing to replace retained publication: {name}")
    accepted, environment = build_acceptance(run, derived_data, metadata)
    published = False
    try:
        write_once(run / ".accepted-evidence.json.staging", accepted)
        inventory = {**accepted["retained_files"],
                     "accepted-evidence.json": file_identity(run / ".accepted-evidence.json.staging")}
        write_once(run / ".retained-file-hashes.json.staging", {"schema": 1, "files": inventory})
        # Validate this exact staged acceptance against the immutable run. The
        # configuration's control path forbids moving the run during validation.
        verify_retained_files(run, ".accepted-evidence.json.staging", ".retained-file-hashes.json.staging")
        result = read_object(run / "raw/iteration-trace.json")
        checked_producer_binding(run, accepted, result, read_object(run / "iteration-trace-config.json"),
                                 startup=accepted["scenario"] == "startup", current_producer=True)
        checked_target_evidence(run, accepted, environment["target"],
                                startup=accepted["scenario"] == "startup" and accepted.get("normalized_metrics_sha256")
                                is not None)
        if accepted["scenario"] == "startup":
            checked_producer_startup(run, result, (accepted["variant"], accepted["scenario"], accepted["iteration"]),
                                     environment["source_revision"], canonical_build(
                                         derived_data, environment["source_revision"])[1], accepted["native_pid"])
        for name in PUBLICATION_NAMES:
            if os.path.lexists(run / name):
                raise ExportError(f"Refusing to replace retained publication: {name}")
        os.link(run / ".accepted-evidence.json.staging", run / "accepted-evidence.json")
        (run / ".accepted-evidence.json.staging").unlink()
        os.link(run / ".retained-file-hashes.json.staging", run / "retained-file-hashes.json")
        verify_retained_files(run)
        published = True
        return accepted
    finally:
        for name in (".accepted-evidence.json.staging", ".retained-file-hashes.json.staging"):
            (run / name).unlink(missing_ok=True)
        if not published:
            # A failure before, during or after the two exclusive link
            # publications is not accepted. Preserve every original producer
            # byte and remove only records created by this invocation.
            for name in PUBLICATION_NAMES:
                (run / name).unlink(missing_ok=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-directory", required=True, type=Path)
    parser.add_argument("--derived-data", required=True, type=Path)
    parser.add_argument("--metadata", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        accepted = finalize_iteration(args.run_directory, args.derived_data, args.metadata)
    except (ExportError, EvidenceError, OSError, KeyError, TypeError, ValueError,
            json.JSONDecodeError, plistlib.InvalidFileException) as error:
        print(f"iteration-finalizer: ERROR: {error}; no complete publication was written", file=sys.stderr)
        return 2
    print(json.dumps({"path": "accepted-evidence.json", "status": accepted["status"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
