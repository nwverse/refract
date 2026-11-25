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
import os
import plistlib
import re
import selectors
import signal
import subprocess
import sys
import time
from fractions import Fraction
from pathlib import Path
from xml.parsers import expat


class LaunchMetricError(ValueError):
    pass


LAUNCH_METRIC = "com.apple.dt.XCTMetric_ApplicationLaunch-AppLaunch.duration"
UNIT_TO_MILLISECONDS = {"s": 1000.0, "seconds": 1000.0}
JSON_BYTE_LIMIT = 16 * 1024 * 1024
JSON_DEPTH_LIMIT = 128
# This local watchdog bounds only xcresulttool after native acquisition. It is
# independent of the 180-second XCTest/native completion deadlines and is not
# a launch-performance threshold. Each of the two exports gets its own budget.
EXPORT_TIMEOUT_SECONDS = 60.0


def traced_test_identifier(variant: str) -> str:
    if variant not in ("generated", "reference"):
        raise LaunchMetricError("A generated or reference startup variant is required")
    return f"RefractBenchUITests/test{variant.capitalize()}StartupTrace()"


def unique_json_object(pairs, label: str) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise LaunchMetricError(f"{label} contains duplicate JSON object key: {key!r}")
        result[key] = value
    return result


def decoded_json(data: bytes, label: str):
    try:
        payload = json.loads(
            data,
            object_pairs_hook=lambda pairs: unique_json_object(pairs, label),
            parse_constant=lambda value: (_ for _ in ()).throw(
                LaunchMetricError(f"{label} contains a non-finite JSON number")))
    except (UnicodeError, json.JSONDecodeError, ValueError, RecursionError) as error:
        raise LaunchMetricError(f"Cannot decode {label}: {error}") from error
    # json.loads can recurse before raising RecursionError. Validate every
    # accepted payload iteratively as well, including direct synthetic callers.
    pending = [(payload, 1)]
    while pending:
        value, depth = pending.pop()
        if depth > JSON_DEPTH_LIMIT:
            raise LaunchMetricError(f"{label} exceeds its {JSON_DEPTH_LIMIT}-level nesting bound")
        if isinstance(value, dict):
            pending.extend((child, depth + 1) for child in value.values())
        elif isinstance(value, list):
            pending.extend((child, depth + 1) for child in value)
    return payload


def file_bytes(path: Path) -> bytes:
    if not path.is_file() or path.is_symlink():
        raise LaunchMetricError(f"Expected an ordinary retained file: {path.name}")
    with path.open("rb") as stream:
        data = stream.read(JSON_BYTE_LIMIT + 1)
    if len(data) > JSON_BYTE_LIMIT:
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
    cases = []
    pending = [payload]
    while pending:
        value = pending.pop()
        if isinstance(value, dict):
            if value.get("nodeType") == "Test Case":
                cases.append(value)
            else:
                pending.extend(value.values())
        elif isinstance(value, list):
            pending.extend(value)
    return cases


def finite_positive(value, label: str) -> float:
    if type(value) not in (int, float):
        raise LaunchMetricError(f"{label} must be a finite positive native number")
    try:
        result = float(value)
    except (OverflowError, ValueError) as error:
        raise LaunchMetricError(f"{label} must be a finite positive native number") from error
    if type(value) is int and int(result) != value:
        raise LaunchMetricError(f"{label} must convert to a finite float without losing integer precision")
    if not math.isfinite(result) or result <= 0:
        raise LaunchMetricError(f"{label} must be a finite positive native number")
    return result


def native_process_identity(run: Path, *, variant: str, revision: str, iteration: int,
                            trace: dict) -> tuple[int, dict[str, dict]]:
    """Match the traced process packets; a receipt PID alone is not native identity."""
    if type(trace.get("session")) is not int:
        raise LaunchMetricError("The trace receipt session must be an integer")
    control = run / "control"
    if not control.is_dir() or control.is_symlink():
        raise LaunchMetricError("The retained native-process control directory must be a real directory")
    paths = {
        "native_process": control / "native-process.json",
        "request": run / "raw/request.json",
        "native_completion": control / "native-completion.json",
        "completion": run / "raw/completion.json",
    }
    packets = {}
    for role, path in paths.items():
        packet = decoded_json(file_bytes(path), f"the {role.replace('_', ' ')} packet")
        if not isinstance(packet, dict):
            raise LaunchMetricError(f"The {role.replace('_', ' ')} packet must be a JSON object")
        packets[role] = packet
    identity = {
        "schema": 1, "session": trace["session"], "revision": revision,
        "variant": variant, "scenario": "startup", "iteration": iteration,
    }
    states = {"native_process": "ready", "request": "ready",
              "native_completion": "complete", "completion": "complete"}
    for role, packet in packets.items():
        for field, value in identity.items():
            if type(packet.get(field)) is not type(value) or packet.get(field) != value:
                raise LaunchMetricError(
                    f"The {role.replace('_', ' ')} packet {field} does not match this startup iteration")
        if packet.get("state") != states[role]:
            raise LaunchMetricError(f"The {role.replace('_', ' ')} packet has the wrong native state")
    native_pid = packets["native_process"].get("pid")
    if type(native_pid) is not int or native_pid <= 0:
        raise LaunchMetricError("The native process PID must be one positive integer")
    for role, packet in packets.items():
        if type(packet.get("pid")) is not int or packet.get("pid") != native_pid:
            raise LaunchMetricError(f"The {role.replace('_', ' ')} packet PID is invalid or unrelated")
        if packet.get("process") != "running":
            raise LaunchMetricError(f"The {role.replace('_', ' ')} packet does not identify a running process")
    if type(trace.get("pid")) is not int or trace.get("pid") != native_pid:
        raise LaunchMetricError("The trace receipt PID must match the native process packet exactly")
    expected_completion = f"{variant} startup complete 1"
    for role in ("native_completion", "completion"):
        if packets[role].get("completion") != expected_completion:
            raise LaunchMetricError(f"The {role.replace('_', ' ')} completion does not match this startup iteration")
    retained = {role: {"path": str(path.relative_to(run)), "sha256": file_sha256(path)}
                for role, path in paths.items()}
    return native_pid, retained


def trace_identity(run: Path, variant: str, revision: str, iteration: int,
                   target_udid: str) -> tuple[dict, dict, int, dict[str, dict]]:
    if not run.is_dir() or run.is_symlink():
        raise LaunchMetricError("The iteration run must be a real retained directory")
    if type(iteration) is not int or iteration not in range(2, 31):
        raise LaunchMetricError("The traced identity must be in 2...30, never a measurement ordinal")
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise LaunchMetricError("A complete source revision is required")
    if not target_udid or any(character in target_udid for character in ("\x00", "\r", "\n")):
        raise LaunchMetricError("A bounded target UDID is required")
    trace = decoded_json(file_bytes(run / "raw/iteration-trace.json"), "the trace receipt")
    expected = {"schema": 1, "source_revision": revision, "variant": variant, "scenario": "startup",
                "iteration": iteration, "target_udid": target_udid, "status": "complete",
                "target_label": "SIMULATOR", "device_result": False,
                "native_iteration_completion": f"{variant} startup complete 1"}
    if (not isinstance(trace, dict)
            or any(type(trace.get(key)) is not type(value) or trace.get(key) != value
                   for key, value in expected.items())):
        raise LaunchMetricError("The native trace receipt does not match this exact startup iteration")
    configuration = decoded_json(file_bytes(run / "iteration-trace-config.json"),
                                 "the trace configuration receipt")
    configuration_path = run / "iteration-trace-config.xctestrun"
    expected_configuration = {"schema": 1, "source_revision": revision, "iteration": iteration,
                              "archive": "iteration-trace-config.xctestrun",
                              "control_directory": str(run / "control")}
    if (not isinstance(configuration, dict)
            or any(type(configuration.get(key)) is not type(value) or configuration.get(key) != value
                   for key, value in expected_configuration.items())
            or type(configuration.get("configuration_sha256")) is not str
            or configuration.get("configuration_sha256") != file_sha256(configuration_path)
            or type(configuration.get("build_provenance_sha256")) is not str
            or configuration.get("build_provenance_sha256")
            != file_sha256(run / "refract-build-provenance.json")):
        raise LaunchMetricError("The retained trace configuration does not match this startup iteration")
    try:
        xctestrun = plistlib.loads(file_bytes(configuration_path))
        environment = xctestrun["RefractBenchUITests"]["TestingEnvironmentVariables"]
    except (OSError, KeyError, TypeError, ValueError, plistlib.InvalidFileException,
            expat.ExpatError) as error:
        raise LaunchMetricError("Cannot decode the retained trace xctestrun") from error
    expected_environment = {"REFRACT_BENCH_REVISION": revision,
                            "REFRACT_BENCH_TRACE_CONTROL": str(run / "control"),
                            "REFRACT_BENCH_TRACE_ITERATION": str(iteration)}
    if (not isinstance(environment, dict)
            or any(environment.get(key) != value for key, value in expected_environment.items())):
        raise LaunchMetricError("The retained xctestrun environment does not match the traced identity")
    native_pid, native_packets = native_process_identity(
        run, variant=variant, revision=revision, iteration=iteration, trace=trace)
    return trace, configuration, native_pid, native_packets


def selected_launch_measurement(metrics, tests, *, variant: str, revision: str, iteration: int,
                                target_udid: str, trace: dict, configuration: dict,
                                native_pid: int, native_packets: dict[str, dict]) -> tuple[dict, float]:
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
    if type(samples[0]) is int:
        milliseconds = Fraction(samples[0]) * 1000
        if (Fraction.from_float(seconds) * 1000 != milliseconds
                or Fraction.from_float(duration_ms) != milliseconds):
            raise LaunchMetricError("The converted launch duration must preserve the exact native integer")
    measurement = {
        "sourceRevision": revision, "variant": variant, "scenario": "startup", "iteration": iteration,
        "pid": native_pid,
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
        "native_pid": native_pid,
        "native_process_packets": native_packets,
    }
    return {"measurements": [measurement],
            "metric_selector": {"index": 0, "value_sha256": hashlib.sha256(canonical).hexdigest()},
            "provenance": provenance}, duration_ms


def _kill_export_process_group(process) -> None:
    """Kill only the new session created for this exporter invocation."""
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        if process.poll() is None:
            process.kill()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def bounded_export_output(command: list[str], run_command) -> bytes:
    """Pump both pipes; never invoke an unbounded capture_output operation."""
    process = run_command(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          start_new_session=True)
    selector = selectors.DefaultSelector()
    stdout_chunks = []
    stdout_size = 0
    stderr_tail = b""
    deadline = time.monotonic() + EXPORT_TIMEOUT_SECONDS
    streams = {}
    try:
        for name, stream in (("stdout", process.stdout), ("stderr", process.stderr)):
            if stream is None:
                raise LaunchMetricError(f"The native export must provide a {name} pipe")
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, name)
            streams[name] = stream
        while streams:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise LaunchMetricError(
                    f"The native xcresult export exceeded its {EXPORT_TIMEOUT_SECONDS:g}-second deadline")
            for key, _ in selector.select(remaining):
                stream = key.fileobj
                name = key.data
                try:
                    chunk = os.read(stream.fileno(), 64 * 1024)
                except BlockingIOError:
                    continue
                if not chunk:
                    selector.unregister(stream)
                    stream.close()
                    del streams[name]
                    continue
                if name == "stdout":
                    stdout_size += len(chunk)
                    if stdout_size > JSON_BYTE_LIMIT:
                        raise LaunchMetricError("The native xcresult stdout exceeds its 16 MiB bound")
                    stdout_chunks.append(chunk)
                else:
                    # Drain stderr without allowing an unbounded diagnostic buffer.
                    stderr_tail = (stderr_tail + chunk)[-64 * 1024:]
        remaining = deadline - time.monotonic()
        try:
            status = process.wait(timeout=max(0.0, remaining))
        except subprocess.TimeoutExpired as error:
            raise LaunchMetricError(
                f"The native xcresult export exceeded its {EXPORT_TIMEOUT_SECONDS:g}-second deadline") from error
        if status != 0:
            raise subprocess.CalledProcessError(status, command, stderr=stderr_tail)
        return b"".join(stdout_chunks)
    finally:
        if process.poll() is None:
            _kill_export_process_group(process)
        selector.close()
        for stream in (process.stdout, process.stderr):
            if stream is not None and not stream.closed:
                stream.close()


def export_launch_metric(run: Path, *, variant: str, revision: str, iteration: int,
                         target_udid: str, run_command=subprocess.Popen) -> dict:
    """Export and preserve only the same result bundle selected by the runner."""
    trace, configuration, native_pid, native_packets = trace_identity(
        run, variant, revision, iteration, target_udid)
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
    output = raw / "metrics.json"
    reserved = [destination / name for name in commands] + [output]
    for path in reserved:
        if path.exists() or path.is_symlink():
            raise LaunchMetricError(f"Refusing to replace existing native export evidence: {path.name}")
    if destination.exists() and (not destination.is_dir() or destination.is_symlink()):
        raise LaunchMetricError("The export directory must be a real directory")
    try:
        # Other benchmark roles may already have retained unrelated resource
        # evidence here. Only this exporter's three target paths are exclusive.
        destination.mkdir(exist_ok=True)
    except FileExistsError as error:
        raise LaunchMetricError("The export directory must be a real directory") from error
    if not destination.is_dir() or destination.is_symlink():
        raise LaunchMetricError("The export directory must be a real directory")
    for name, command in commands.items():
        data = bounded_export_output(command, run_command)
        write_once(destination / name, data)
        exports[name] = data
    trace["path"] = run / "raw/iteration-trace.json"
    configuration["path"] = run / "iteration-trace-config.json"
    tests = decoded_json(exports["xctest-tests.json"], "the XCTest tests export")
    metrics = decoded_json(exports["xctest-metrics.json"], "the XCTest metrics export")
    selected, duration_ms = selected_launch_measurement(
        metrics, tests, variant=variant, revision=revision, iteration=iteration,
        target_udid=target_udid, trace=trace, configuration=configuration,
        native_pid=native_pid, native_packets=native_packets)
    selected["provenance"]["export_commands"] = list(commands.values())
    selected["provenance"]["raw_exports"] = {
        name: {"path": f"raw/exports/{name}", "sha256": hashlib.sha256(data).hexdigest()}
        for name, data in exports.items()
    }
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
    except (LaunchMetricError, OSError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired) as error:
        print(f"launch-metric: ERROR: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
