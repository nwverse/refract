#!/usr/bin/env python3
"""Export one native XCTApplicationLaunchMetric duration for a traced startup test.

This reads an already acquired xcresult; it never launches a target, XCTest or
Instruments. The runner invokes it only after its exact traced XCTest passes.
The retained trace/configuration identity supplies the 2...30 iteration; an
XCTest measurement ordinal never supplies that identity.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import plistlib
import re
import subprocess
import sys
from pathlib import Path


class LaunchMetricError(ValueError):
    pass


LAUNCH_METRIC = "com.apple.dt.XCTMetric_ApplicationLaunch-AppLaunch.duration"
UNIT_TO_MILLISECONDS = {"s": 1000.0, "seconds": 1000.0}


def traced_test_identifier(variant: str) -> str:
    if variant not in ("generated", "reference"):
        raise LaunchMetricError("A generated or reference startup variant is required")
    return f"RefractBenchUITests/test{variant.capitalize()}StartupTrace()"


def decoded_json(data: bytes, label: str):
    try:
        return json.loads(data, parse_constant=lambda value: (_ for _ in ()).throw(
            LaunchMetricError(f"{label} contains a non-finite JSON number")))
    except (UnicodeError, json.JSONDecodeError, ValueError) as error:
        raise LaunchMetricError(f"Cannot decode {label}: {error}") from error


def file_bytes(path: Path) -> bytes:
    if not path.is_file() or path.is_symlink():
        raise LaunchMetricError(f"Expected an ordinary retained file: {path.name}")
    with path.open("rb") as stream:
        data = stream.read(16 * 1024 * 1024 + 1)
    if len(data) > 16 * 1024 * 1024:
        raise LaunchMetricError(f"Retained JSON exceeds its 16 MiB bound: {path.name}")
    return data


def file_sha256(path: Path) -> str:
    return hashlib.sha256(file_bytes(path)).hexdigest()


def write_once(path: Path, data: bytes) -> None:
    if path.exists() or path.is_symlink():
        raise LaunchMetricError(f"Refusing to replace retained evidence: {path.name}")
    with path.open("xb") as stream:
        stream.write(data)


def test_cases(payload) -> list[dict]:
    if isinstance(payload, dict):
        if payload.get("nodeType") == "Test Case":
            return [payload]
        return [case for value in payload.values() for case in test_cases(value)]
    if isinstance(payload, list):
        return [case for value in payload for case in test_cases(value)]
    return []


def finite_positive(value, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise LaunchMetricError(f"{label} must be a finite positive native number")
    try:
        result = float(value)
    except (OverflowError, ValueError) as error:
        raise LaunchMetricError(f"{label} must be a finite positive native number") from error
    if not math.isfinite(result) or result <= 0:
        raise LaunchMetricError(f"{label} must be a finite positive native number")
    return result


def trace_identity(run: Path, variant: str, revision: str, iteration: int,
                   target_udid: str) -> tuple[dict, dict]:
    if not run.is_dir() or run.is_symlink():
        raise LaunchMetricError("The iteration run must be a real retained directory")
    if type(iteration) is not int or iteration not in range(2, 31):
        raise LaunchMetricError("The traced identity must be in 2...30, never a measurement ordinal")
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise LaunchMetricError("A complete source revision is required")
    if not target_udid or any(character in target_udid for character in ("\x00", "\r", "\n")):
        raise LaunchMetricError("A bounded target UDID is required")
    trace = decoded_json(file_bytes(run / "raw/iteration-trace.json"), "the trace receipt")
    expected = {"source_revision": revision, "variant": variant, "scenario": "startup",
                "iteration": iteration, "target_udid": target_udid, "status": "complete",
                "target_label": "SIMULATOR", "device_result": False,
                "native_iteration_completion": f"{variant} startup complete 1"}
    if not isinstance(trace, dict) or any(trace.get(key) != value for key, value in expected.items()):
        raise LaunchMetricError("The native trace receipt does not match this exact startup iteration")
    configuration = decoded_json(file_bytes(run / "iteration-trace-config.json"),
                                 "the trace configuration receipt")
    configuration_path = run / "iteration-trace-config.xctestrun"
    if (not isinstance(configuration, dict) or configuration.get("schema") != 1
            or configuration.get("source_revision") != revision
            or configuration.get("iteration") != iteration
            or configuration.get("archive") != "iteration-trace-config.xctestrun"
            or configuration.get("control_directory") != str(run / "control")
            or configuration.get("configuration_sha256") != file_sha256(configuration_path)
            or configuration.get("build_provenance_sha256")
            != file_sha256(run / "refract-build-provenance.json")):
        raise LaunchMetricError("The retained trace configuration does not match this startup iteration")
    try:
        xctestrun = plistlib.loads(file_bytes(configuration_path))
        environment = xctestrun["RefractBenchUITests"]["TestingEnvironmentVariables"]
    except (OSError, KeyError, TypeError, ValueError, plistlib.InvalidFileException) as error:
        raise LaunchMetricError("Cannot decode the retained trace xctestrun") from error
    expected_environment = {"REFRACT_BENCH_REVISION": revision,
                            "REFRACT_BENCH_TRACE_CONTROL": str(run / "control"),
                            "REFRACT_BENCH_TRACE_ITERATION": str(iteration)}
    if (not isinstance(environment, dict)
            or any(environment.get(key) != value for key, value in expected_environment.items())):
        raise LaunchMetricError("The retained xctestrun environment does not match the traced identity")
    return trace, configuration


def selected_launch_measurement(metrics, tests, *, variant: str, revision: str, iteration: int,
                                target_udid: str, trace: dict, configuration: dict) -> tuple[dict, float]:
    identifier = traced_test_identifier(variant)
    cases = test_cases(tests)
    if len(cases) != 1:
        raise LaunchMetricError("The same xcresult must contain exactly one traced startup test case")
    case = cases[0]
    expected_url = ("test://com.apple.xcode/RefractBench/RefractBenchUITests/"
                    f"RefractBenchUITests/test{variant.capitalize()}StartupTrace")
    if (case.get("nodeIdentifier") != identifier or case.get("name") != identifier
            or case.get("nodeIdentifierURL") != expected_url or case.get("result") != "Passed"):
        raise LaunchMetricError("The XCTest result is not the passing exact traced startup selector")
    finite_positive(case.get("durationInSeconds"), "The test-case duration")
    if not isinstance(metrics, list) or len(metrics) != 1 or not isinstance(metrics[0], dict):
        raise LaunchMetricError("The exact-selector metrics export must contain exactly one test")
    selected_test = metrics[0]
    if (selected_test.get("testIdentifier") != identifier
            or selected_test.get("testIdentifierURL", expected_url) != expected_url):
        raise LaunchMetricError("The launch metric belongs to a different XCTest selector")
    runs = selected_test.get("testRuns")
    if not isinstance(runs, list) or len(runs) != 1 or not isinstance(runs[0], dict):
        raise LaunchMetricError("The exact traced startup selector must have exactly one test run")
    native_run = runs[0]
    device = native_run.get("device")
    if not isinstance(device, dict) or device.get("deviceId") != target_udid:
        raise LaunchMetricError("The launch metric belongs to a different target")
    configurations = tests.get("testPlanConfigurations") if isinstance(tests, dict) else None
    if (not isinstance(configurations, list) or len(configurations) != 1
            or native_run.get("testPlanConfiguration") != configurations[0]):
        raise LaunchMetricError("The launch metric and selected test must share one test-plan configuration")
    native_metrics = native_run.get("metrics")
    if not isinstance(native_metrics, list) or len(native_metrics) != 1:
        raise LaunchMetricError("The traced startup selector must export exactly one native launch metric")
    native_metric = native_metrics[0]
    if not isinstance(native_metric, dict) or native_metric.get("identifier") != LAUNCH_METRIC:
        raise LaunchMetricError("The selected native metric is not XCTApplicationLaunchMetric duration")
    multiplier = UNIT_TO_MILLISECONDS.get(native_metric.get("unitOfMeasurement"))
    if multiplier is None:
        raise LaunchMetricError("The native launch metric must explicitly use seconds")
    samples = native_metric.get("measurements")
    if not isinstance(samples, list) or len(samples) != 1:
        raise LaunchMetricError("Exactly one native launch-duration sample is required; empty or repeated values fail")
    seconds = finite_positive(samples[0], "The native launch duration")
    duration_ms = finite_positive(seconds * multiplier, "The converted launch duration")
    measurement = {
        "sourceRevision": revision, "variant": variant, "scenario": "startup", "iteration": iteration,
        "metric": "XCTApplicationLaunchMetric", "nativeMetricIdentifier": LAUNCH_METRIC,
        "nativeTestIdentifier": identifier,
        "nativeValue": {"unitOfMeasurement": native_metric["unitOfMeasurement"], "measurements": samples},
        "value": {"definition": "XCTApplicationLaunchMetric", "unit": "ms", "duration_ms": duration_ms},
    }
    canonical = json.dumps(measurement, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    provenance = {
        "native_test_identifier_url": expected_url,
        "trace_receipt_sha256": file_sha256(trace["path"]),
        "trace_configuration_receipt_sha256": file_sha256(configuration["path"]),
    }
    return {"measurements": [measurement],
            "metric_selector": {"index": 0, "value_sha256": hashlib.sha256(canonical).hexdigest()},
            "provenance": provenance}, duration_ms


def export_launch_metric(run: Path, *, variant: str, revision: str, iteration: int,
                         target_udid: str, run_command=subprocess.run) -> dict:
    """Export and preserve only the same result bundle selected by the runner."""
    trace, configuration = trace_identity(run, variant, revision, iteration, target_udid)
    results = run / "results.xcresult"
    if (not results.is_dir() or results.is_symlink()
            or not (results / "Info.plist").is_file() or (results / "Info.plist").is_symlink()):
        raise LaunchMetricError("A real retained results.xcresult is required")
    identifier = traced_test_identifier(variant)
    commands = {
        "xctest-tests.json": ["xcrun", "xcresulttool", "get", "test-results", "tests",
                              "--path", str(results), "--format", "json"],
        "xctest-metrics.json": ["xcrun", "xcresulttool", "get", "test-results", "metrics",
                                "--path", str(results), "--format", "json", "--test-id", identifier],
    }
    exports = {}
    raw = run / "raw"
    if not raw.is_dir() or raw.is_symlink():
        raise LaunchMetricError("The retained raw directory must be a real directory")
    destination = raw / "exports"
    try:
        destination.mkdir(exist_ok=False)
    except FileExistsError as error:
        raise LaunchMetricError("Refusing to reuse an existing export directory") from error
    if not destination.is_dir() or destination.is_symlink():
        raise LaunchMetricError("The export directory must be a real directory")
    for name, command in commands.items():
        completed = run_command(command, check=True, capture_output=True)
        if not isinstance(completed.stdout, bytes):
            raise LaunchMetricError("The native export must retain its exact JSON bytes")
        write_once(destination / name, completed.stdout)
        exports[name] = completed.stdout
    trace["path"] = run / "raw/iteration-trace.json"
    configuration["path"] = run / "iteration-trace-config.json"
    tests = decoded_json(exports["xctest-tests.json"], "the XCTest tests export")
    metrics = decoded_json(exports["xctest-metrics.json"], "the XCTest metrics export")
    selected, duration_ms = selected_launch_measurement(
        metrics, tests, variant=variant, revision=revision, iteration=iteration,
        target_udid=target_udid, trace=trace, configuration=configuration)
    selected["provenance"]["export_commands"] = list(commands.values())
    selected["provenance"]["raw_exports"] = {
        name: {"path": f"raw/exports/{name}", "sha256": hashlib.sha256(data).hexdigest()}
        for name, data in exports.items()
    }
    output = raw / "metrics.json"
    write_once(output, (json.dumps(selected, indent=2, sort_keys=True, allow_nan=False) + "\n").encode())
    return {"path": "raw/metrics.json", "sha256": file_sha256(output), "duration_ms": duration_ms,
            "metric_selector": selected["metric_selector"]}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-directory", required=True, type=Path)
    parser.add_argument("--variant", required=True, choices=("generated", "reference"))
    parser.add_argument("--iteration", required=True, type=int)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--target-udid", required=True)
    args = parser.parse_args(argv)
    try:
        result = export_launch_metric(args.run_directory, variant=args.variant, revision=args.source_revision,
                                      iteration=args.iteration, target_udid=args.target_udid)
    except (LaunchMetricError, OSError, subprocess.CalledProcessError) as error:
        print(f"launch-metric: ERROR: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
