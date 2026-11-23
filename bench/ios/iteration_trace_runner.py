#!/usr/bin/env python3
"""Capture one exact, already-running iOS benchmark iteration with Instruments.

The selected XCTest exposes the application PID and waits for this driver to
confirm recorder readiness. No target is created, booted, rebooted or reused by
filename. This driver does not produce a paired performance report.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import plistlib
import re
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from archive_trace import ArchiveError, archive_trace


class HandshakeError(ValueError):
    pass


VARIANTS = ("generated", "reference")
SCENARIOS = ("scroll", "stateUpdate", "startup")
TARGET_PROBE_FILENAMES = ("targets.json", "simulators.json", "target.json")
READY_OUTPUT = re.compile(r"(?:^|\n)Starting recording with the (.+?) template\.[^\n]*(?:\n|$)")
SAVED_OUTPUT = re.compile(r"(?:^|\n)Output (?:file saved as|saved):[ \t]*(.+?)[ \t]*(?=\n|$)")


def atomic_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        with temporary.open("x", encoding="utf-8") as stream:
            json.dump(payload, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, path)
    except FileExistsError as error:
        raise HandshakeError(f"Refusing to replace handshake evidence: {path}") from error
    finally:
        temporary.unlink(missing_ok=True)


def bounded_file_bytes(path: Path) -> bytes:
    bounded_regular_file(path)
    with path.open("rb") as stream:
        data = stream.read(MAX_EVIDENCE_FILE_BYTES + 1)
    if len(data) > MAX_EVIDENCE_FILE_BYTES:
        raise HandshakeError(f"Evidence file exceeds the {MAX_EVIDENCE_FILE_BYTES}-byte bound: {path.name}")
    return data


def read_json(path: Path) -> dict:
    try:
        payload = json.loads(bounded_file_bytes(path))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise HandshakeError(f"Cannot read handshake {path.name}: {error}") from error
    if not isinstance(payload, dict):
        raise HandshakeError(f"Handshake {path.name} must be a JSON object")
    return payload


def checked_identity(packet: dict, session: "Session") -> None:
    expected = {
        "schema": 1,
        "session": session.session_id,
        "revision": session.revision,
        "variant": session.variant,
        "scenario": session.scenario,
        "iteration": session.iteration,
    }
    for field, value in expected.items():
        if packet.get(field) != value:
            raise HandshakeError(
                f"Stale or mismatched iteration identity in {field}: expected {value!r}, got {packet.get(field)!r}")


def unique_packet(directory: Path, stem: str, session: "Session") -> dict:
    if not directory.is_dir() or directory.is_symlink():
        raise HandshakeError("Control directory must be a real directory")
    matches = sorted(path for path in directory.glob(f"{stem}*.json") if path.is_file() and not path.is_symlink())
    if not matches:
        raise HandshakeError(f"Missing {stem} packet: expected exactly {stem}.json")
    if len(matches) != 1 or matches[0].name != f"{stem}.json":
        raise HandshakeError(f"Ambiguous {stem} packets: expected exactly {stem}.json")
    packet = read_json(matches[0])
    checked_identity(packet, session)
    return packet


def wait_for(check, timeout: float, description: str, interrupted=None):
    deadline = time.monotonic() + timeout
    while True:
        result = check()
        if result is not None:
            return result
        if interrupted is not None:
            interrupted()
        if time.monotonic() >= deadline:
            raise HandshakeError(f"Timed out waiting for {description}")
        time.sleep(0.01)


def checked_first_display(packet: dict) -> dict:
    """Retain app-recorded monotonic first-display evidence, never elapsed shell time."""
    evidence = packet.get("firstDisplay")
    if (not isinstance(evidence, dict) or set(evidence) != {"clock", "timestamp"}
            or evidence.get("clock") != "CACurrentMediaTime"):
        raise HandshakeError("Startup completion requires exact native first-display evidence")
    text = evidence.get("timestamp")
    if type(text) is not str:
        raise HandshakeError("Startup first-display timestamp must be an exact decimal string")
    try:
        timestamp = float(text)
    except ValueError as error:
        raise HandshakeError("Startup first-display timestamp must be an exact decimal string") from error
    if not math.isfinite(timestamp) or timestamp <= 0 or repr(timestamp) != text:
        raise HandshakeError("Startup first-display timestamp must round-trip as one finite positive Double")
    return evidence


class Session:
    """One non-reusable variant/scenario/iteration/recorder binding."""

    def __init__(self, *, target: str, variant: str, scenario: str, iteration: int,
                 revision: str, run_directory: Path, xcodebuild_log: Path,
                 control_directory: Path, readiness_timeout: float = 60,
                 completion_timeout: float = 180, window: str = "5s",
                 template: str = "Animation Hitches", session_id: int = 1,
                 target_label: str = "SIMULATOR", derived_data: Path | None = None,
                 target_probe_files: tuple[Path, ...] = ()):
        if variant not in VARIANTS or scenario not in SCENARIOS:
            raise HandshakeError("Unsupported variant or scenario")
        if iteration not in range(30):
            raise HandshakeError("Iteration must be in 0..29")
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise HandshakeError("A committed 40-character source revision is required")
        if not re.fullmatch(r"[1-9][0-9]*(s|ms)", window):
            raise HandshakeError("The Instruments window must be a positive explicit duration")
        if target_label != "SIMULATOR":
            raise HandshakeError("This driver currently supports only a probed simulator; it is not device evidence")
        expected_probes = tuple(run_directory / name for name in TARGET_PROBE_FILENAMES)
        if target_probe_files and (target_probe_files != expected_probes or any(
                not path.is_file() or path.is_symlink() for path in target_probe_files)):
            raise HandshakeError("Current target probes must be ordinary files generated in this run directory")
        self.target = target
        self.variant = variant
        self.scenario = scenario
        self.iteration = iteration
        self.revision = revision
        self.run_directory = run_directory
        self.xcodebuild_log = xcodebuild_log
        self.control_directory = control_directory
        self.readiness_timeout = readiness_timeout
        self.completion_timeout = completion_timeout
        self.window = window
        self.template = template
        self.session_id = session_id
        self.target_label = target_label
        self.derived_data = derived_data
        self.target_probe_files = target_probe_files
        self.raw = run_directory / "raw"
        self.identity = f"{variant}-{scenario}-{iteration}"
        self.trace = run_directory / f"{self.identity}.trace"
        self.archive = self.raw / f"{self.identity}.trace.zip"

    def capture(self, test_process: subprocess.Popen, recorder_factory=None) -> dict:
        if self.run_directory.exists() and any(self.run_directory.iterdir()):
            # The caller creates a new run directory for the test log and empty
            # control directory before capture. The ordinary CLI explicitly admits
            # its current target probes; preparation retains this run's configuration
            # and build provenance. No other pre-existing content is accepted.
            allowed = {self.xcodebuild_log, self.control_directory,
                       self.run_directory / "iteration-trace-config.json",
                       self.run_directory / "iteration-trace-config.xctestrun",
                       self.run_directory / BUILD_PROVENANCE_NAME, *self.target_probe_files}
            unexpected = [p for p in self.run_directory.iterdir() if p not in allowed]
            if unexpected or not self.xcodebuild_log.is_file():
                raise HandshakeError("A new run directory contains unexpected or stale files")
        if not self.xcodebuild_log.is_file():
            raise HandshakeError("The current xcodebuild log is missing")
        self.control_directory.mkdir(parents=True, exist_ok=True)
        # XCTest may publish its identity while the build is being verified.
        # Reject reused control state before this slow validation, then let the
        # ordinary request/ready/completion waits admit only this run's packets.
        # No completion is valid before this capture publishes recorder-ready.
        if any(self.control_directory.iterdir()):
            raise HandshakeError("Refusing a reused or stale control directory")
        if self.derived_data is not None:
            validate_build_provenance(self.derived_data, self.revision)
        validate_trace_configuration(self.run_directory, self.revision, self.control_directory, self.iteration,
                                     self.derived_data)
        self.raw.mkdir(exist_ok=False)
        recorder = None
        reader = None
        recorder_log = self.raw / "recorder.log"
        stream = recorder_log.open("x", encoding="utf-8")
        if recorder_factory is None:
            def recorder_factory(command, log):
                return subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        text=True, bufsize=1)
        try:
            request = wait_for(lambda: self._request_if_present(), self.readiness_timeout,
                               "an exact running application PID", lambda: self._check_test(test_process))
            pid = request.get("pid")
            if type(pid) is not int or pid <= 0:
                raise HandshakeError(f"Application PID must be one positive integer, got {pid!r}")
            if request.get("process") != "running":
                raise HandshakeError(f"Application process is not running: {request.get('process')!r}")
            atomic_json(self.raw / "request.json", request)

            command = ["xcrun", "xctrace", "record", "--device", self.target,
                       "--template", self.template, "--attach", str(pid),
                       "--window", self.window, "--output", str(self.trace)]
            recorder = recorder_factory(command, stream)
            reader = threading.Thread(target=self._collect_output, args=(recorder, stream), daemon=True)
            reader.start()
            wait_for(lambda: self._readiness_if_valid(recorder), self.readiness_timeout,
                     "Instruments readiness", lambda: self._check_test(test_process))
            # XCTest must not release the app until this durable acknowledgement
            # exists. PID and iteration identity are repeated to prevent reuse.
            acknowledgement = dict(request, state="recorder-ready", recorder_pid=recorder.pid,
                                   trace=str(self.trace))
            atomic_json(self.control_directory / "recorder-ready.json", acknowledgement)
            atomic_json(self.raw / "recorder-ready.json", acknowledgement)

            completion = wait_for(lambda: self._completion_if_present(), self.completion_timeout,
                                  "the exact native iteration completion",
                                  lambda: self._recorder_exit_after_ready(recorder))
            if completion.get("state") != "complete":
                raise HandshakeError("The application completion state is not complete")
            first_display = checked_first_display(completion) if self.scenario == "startup" else None
            # Accessibility reports this launch's native completion count (one),
            # not a cumulative count from the retired single-launch task.
            expected_completion = f"{self.variant} {self.scenario} complete 1"
            if (completion.get("completion") != expected_completion or completion.get("pid") != pid
                    or completion.get("process") != "running"):
                raise HandshakeError("The native completion, process state or PID does not match this iteration")
            # XCTest may return as soon as the app terminates. Its final exit
            # status is checked by main after this recorder is fully stopped.
            atomic_json(self.raw / "completion.json", completion)

            # Ask only our xctrace child to stop gracefully (SIGINT is the
            # Instruments interrupt path), flush its package, then release XCTest.
            atomic_json(self.control_directory / "recorder-stop", {"session": self.session_id})
            if recorder.poll() is None:
                try:
                    recorder.send_signal(signal.SIGINT)
                except ProcessLookupError:
                    # The recorder exited between poll and SIGINT; wait below
                    # preserves its actual status instead of masking it.
                    pass
            try:
                status = recorder.wait(timeout=20)
            except subprocess.TimeoutExpired as error:
                recorder.kill()
                recorder.wait(timeout=5)
                raise HandshakeError("Instruments did not stop after the exact iteration") from error
            reader.join(timeout=5)
            if reader.is_alive():
                raise HandshakeError("Instruments output collection did not finish")
            if status != 0:
                raise HandshakeError(f"Instruments recorder exited with status {status}; trace is not accepted")
            saved = SAVED_OUTPUT.findall(self._output)
            if len(saved) != 1 or not saved_trace_matches(saved[0], self.trace):
                raise HandshakeError("Instruments did not save the exact requested trace package")
            size, checksum = archive_trace(self.trace, self.archive)
            finished = dict(completion, state="recorder-finished", recorder_exit=status,
                            trace=str(self.trace), archived_package=self.archive.name)
            atomic_json(self.control_directory / "recorder-finished.json", finished)
            atomic_json(self.raw / "recorder-finished.json", finished)
            result = {
                "schema": 1, "status": "complete", "session": self.session_id,
                "source_revision": self.revision, "variant": self.variant,
                "scenario": self.scenario, "iteration": self.iteration, "pid": pid,
                "target_udid": self.target, "target_label": self.target_label,
                "device_result": False, "recorder": "xctrace", "template": self.template,
                "time_limit": self.window, "trace": f"raw/{self.archive.name}",
                "archived_package_name": self.trace.name, "bytes": size, "sha256": checksum,
                "native_iteration_completion": expected_completion,
            }
            validate_trace_configuration(self.run_directory, self.revision, self.control_directory, self.iteration,
                                     self.derived_data)
            if self.derived_data is not None:
                validate_build_provenance(self.derived_data, self.revision)
            if first_display is not None:
                result["native_first_display"] = first_display
            atomic_json(self.raw / "iteration-trace.json", result)
            return result
        finally:
            if recorder is not None and recorder.poll() is None:
                recorder.terminate()
                try:
                    recorder.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    recorder.kill()
                    recorder.wait(timeout=5)
            if reader is not None:
                reader.join(timeout=5)
            stream.close()

    def _request_if_present(self):
        path = self.control_directory / "request.json"
        if not path.exists():
            return None
        return unique_packet(self.control_directory, "request", self)

    def _completion_if_present(self):
        path = self.control_directory / "completion.json"
        if path.exists():
            return unique_packet(self.control_directory, "completion", self)
        return None

    def _recorder_exit_after_ready(self, recorder: subprocess.Popen):
        status = recorder.poll()
        if status is None:
            return None
        # A completion published concurrently with a recorder failure must not
        # be misreported as no completion, and can never accept the trace.
        if (self.control_directory / "completion.json").exists():
            raise HandshakeError(f"Instruments recorder exited with status {status}; trace is not accepted")
        raise HandshakeError(f"Instruments recorder exited before native completion with status {status}")

    def _readiness_if_valid(self, recorder: subprocess.Popen):
        status = recorder.poll()
        if status is not None:
            raise HandshakeError(f"Instruments recorder exited before readiness with status {status}")
        # xctrace explicitly reports that its recording template has started.
        # Process launch, a blank stream or a filename alone is not readiness.
        if not hasattr(self, "_output"):
            return None
        templates = READY_OUTPUT.findall(self._output)
        if len(templates) != 1:
            return None
        if templates[0] != self.template:
            raise HandshakeError(f"Instruments started a different template: {templates[0]}")
        if self.trace.exists() and self.trace.is_symlink():
            raise HandshakeError("Instruments trace path must not be a symbolic link")
        return True

    def _collect_output(self, recorder: subprocess.Popen, stream):
        self._output = ""
        for line in recorder.stdout:
            stream.write(line)
            stream.flush()
            self._output += line
        recorder.stdout.close()

    def _check_test(self, process: subprocess.Popen):
        if process.poll() is not None:
            raise HandshakeError(f"Xcode test exited before completion with status {process.returncode}")

    def _check_recorder(self, process: subprocess.Popen):
        if process.poll() is not None:
            raise HandshakeError(f"Instruments recorder exited before native completion with status {process.returncode}")


MAX_EVIDENCE_FILE_BYTES = 64 * 1024 * 1024
BUILD_PROVENANCE_NAME = "refract-build-provenance.json"
BUNDLE_NAMES = ("RefractBench.app", "RefractBenchUITests-Runner.app",
                "RefractBenchUITests-Runner.app/PlugIns/RefractBenchUITests.xctest")


def bounded_regular_file(path: Path) -> os.stat_result:
    path = path.absolute()
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode):
        raise HandshakeError(f"Expected a bounded ordinary file, not a link, directory or special file: {path.name}")
    if metadata.st_size > MAX_EVIDENCE_FILE_BYTES:
        raise HandshakeError(f"Evidence file exceeds the {MAX_EVIDENCE_FILE_BYTES}-byte bound: {path.name}")
    return metadata


def file_sha256(path: Path) -> str:
    bounded_regular_file(path)
    digest = hashlib.sha256()
    for offset in range(0, len(data := bounded_file_bytes(path)), 1024 * 1024):
        digest.update(data[offset:offset + 1024 * 1024])
    return digest.hexdigest()


def bundle_identity(products: Path, relative: str) -> dict:
    bundle = products / relative
    if not bundle.is_dir() or bundle.is_symlink():
        raise HandshakeError(f"Build product is not a real bundle directory: {relative}")
    files = []
    directories = []
    for directory, directory_names, file_names in os.walk(bundle, topdown=True, followlinks=False):
        directory_names.sort()
        file_names.sort()
        for name in (*directory_names, *file_names):
            path = Path(directory) / name
            mode = path.lstat().st_mode
            if not stat.S_ISDIR(mode) and not stat.S_ISREG(mode):
                raise HandshakeError(f"Build product contains a symbolic link or special file: {relative}")
    for directory, directory_names, file_names in os.walk(bundle, followlinks=False):
        directory_names.sort()
        directories.extend((Path(directory) / name).relative_to(products).as_posix()
                           for name in sorted(directory_names))
        for name in sorted(file_names):
            path = Path(directory) / name
            files.append({"path": path.relative_to(products).as_posix(),
                          "bytes": path.stat(follow_symlinks=False).st_size,
                          "executable": bool(path.stat(follow_symlinks=False).st_mode & 0o111),
                          "sha256": file_sha256(path)})
    if not files:
        raise HandshakeError(f"Build product bundle has no files: {relative}")
    try:
        executable = plistlib.loads(bounded_file_bytes(bundle / "Info.plist")).get("CFBundleExecutable")
    except (OSError, plistlib.InvalidFileException) as error:
        raise HandshakeError(f"Build product bundle Info.plist is missing or invalid: {relative}") from error
    expected_executable = f"{relative}/{executable}" if isinstance(executable, str) and executable else ""
    if not any(item["path"] == expected_executable for item in files):
        raise HandshakeError(f"Build product CFBundleExecutable is missing from its identity: {relative}")
    return {"directories": sorted(directories), "files": files}


def generated_test_runs(derived_data: Path) -> list[Path]:
    sources = sorted(path for path in (derived_data / "Build/Products").glob("*.xctestrun")
                     if path.name != "iteration-trace-config.xctestrun"
                     and not path.name.startswith("iteration-trace-config-"))
    if len(sources) != 1 or sources[0].is_symlink():
        raise HandshakeError("Exactly one original generated xctestrun file is required")
    bounded_regular_file(sources[0])
    return sources


def record_build_provenance(derived_data: Path, revision: str, destination: Path | None = None) -> dict:
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise HandshakeError("Build provenance requires a committed 40-character source revision")
    products = derived_data / "Build/Products/Release-iphonesimulator"
    sources = generated_test_runs(derived_data)
    manifest = {"schema": 1, "source_revision": revision, "configuration": "Release-iphonesimulator",
                "source_xctestrun": {"path": sources[0].name, "sha256": file_sha256(sources[0])},
                "products": {name: bundle_identity(products, name) for name in BUNDLE_NAMES}}
    path = destination or derived_data / BUILD_PROVENANCE_NAME
    atomic_json(path, manifest)
    return {**manifest, "path": path}


def validate_build_provenance(derived_data: Path, revision: str) -> dict:
    path = derived_data / BUILD_PROVENANCE_NAME
    if not path.is_file() or path.is_symlink():
        raise HandshakeError("Build provenance manifest is missing; rebuild these products with build.sh")
    try:
        if (not path.parent.is_dir() or path.parent.is_symlink()
                or (path.exists() and not path.is_file()) or path.is_symlink()):
            raise HandshakeError("Build provenance must be an ordinary file in a real DerivedData directory")
        manifest = read_json(path)
        if manifest.get("schema") != 1 or manifest.get("source_revision") != revision:
            raise HandshakeError("Build product source revision does not match the requested current HEAD")
        if manifest.get("configuration") != "Release-iphonesimulator":
            raise HandshakeError("Build product configuration does not match the trace destination")
        expected_products = manifest.get("products")
        source = manifest.get("source_xctestrun")
        sources = generated_test_runs(derived_data)
        expected_source = {"path": sources[0].name, "sha256": file_sha256(sources[0])}
        if source != expected_source:
            raise HandshakeError("The original xctestrun changed; rebuild the build-for-testing products")
        if not isinstance(expected_products, dict) or set(expected_products) != set(BUNDLE_NAMES):
            raise HandshakeError("Build provenance does not identify exactly the app and test bundles")
        products = derived_data / "Build/Products/Release-iphonesimulator"
        for name in BUNDLE_NAMES:
            expected = bundle_identity(products, name)
            if expected_products[name] != expected:
                raise HandshakeError(f"Build product file digest or identity changed: {name}; rebuild with build.sh")
        return {**manifest, "path": path}
    except (KeyError, TypeError, ValueError, OSError) as error:
        if isinstance(error, HandshakeError):
            raise
        raise HandshakeError(f"Invalid build provenance manifest: {error}") from error


def original_test_run(derived_data: Path, build_provenance: dict) -> Path:
    if build_provenance.get("schema") != 1 or "path" not in build_provenance:
        raise HandshakeError("Validated build provenance is required before reading an xctestrun")
    sources = generated_test_runs(derived_data)
    return sources[0]


def traced_test_name(variant: str, scenario: str) -> str:
    """Return the existing Swift XCTest selector without changing its camel case."""
    selector = {"scroll": "Scroll", "stateUpdate": "StateUpdate", "startup": "Startup"}[scenario]
    return f"RefractBenchUITests/RefractBenchUITests/test{variant.capitalize()}{selector}Trace"


def test_command(test_run: Path, target_udid: str, test: str, revision: str,
                 results: Path) -> list[str]:
    return ["xcodebuild", "test-without-building", "-xctestrun", str(test_run),
            "-resultBundlePath", str(results), "-destination", f"platform=iOS Simulator,id={target_udid}",
            f"-only-testing:{test}", "CODE_SIGNING_ALLOWED=NO", f"REFRACT_BENCH_REVISION={revision}"]


def checked_trace_environment(destination: Path, values: dict) -> None:
    extracted = subprocess.run(["plutil", "-extract",
                                "RefractBenchUITests.TestingEnvironmentVariables", "json",
                                "-o", "-", str(destination)], check=True, capture_output=True, text=True)
    try:
        environment = json.loads(extracted.stdout)
        if not isinstance(environment, dict):
            raise TypeError("the hosted-test environment must be an object")
        if any(environment.get(name) != value for name, value in values.items()):
            raise HandshakeError("The final trace revision, control directory and iteration do not match this run")
    except (json.JSONDecodeError, TypeError) as error:
        raise HandshakeError("Cannot verify the final trace configuration") from error


def validate_trace_configuration(run_directory: Path, revision: str, control: Path, iteration: int,
                                 derived_data: Path | None = None) -> dict:
    receipt = read_json(run_directory / "iteration-trace-config.json")
    if (receipt.get("schema") != 1 or receipt.get("source_revision") != revision
            or receipt.get("control_directory") != str(control) or receipt.get("iteration") != iteration):
        raise HandshakeError("Trace configuration revision, control directory or iteration does not match this run")
    manifest = run_directory / BUILD_PROVENANCE_NAME
    if file_sha256(manifest) != receipt.get("build_provenance_sha256"):
        raise HandshakeError("Archived build provenance no longer matches this iteration")
    archived = run_directory / "iteration-trace-config.xctestrun"
    if archived.is_symlink() or file_sha256(archived) != receipt.get("configuration_sha256"):
        raise HandshakeError("Archived trace configuration no longer matches this iteration")
    destination = derived_from_receipt(receipt, derived_data)
    configuration_sha256 = receipt.get("configuration_sha256")
    if not isinstance(configuration_sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", configuration_sha256):
        raise HandshakeError("Trace configuration receipt has no valid configuration SHA-256")
    if destination.is_symlink() or file_sha256(destination) != configuration_sha256:
        raise HandshakeError("The trace configuration to execute differs from its retained bytes")
    values = {"REFRACT_BENCH_REVISION": revision,
              "REFRACT_BENCH_TRACE_CONTROL": str(control),
              "REFRACT_BENCH_TRACE_ITERATION": str(iteration)}
    checked_trace_environment(destination, values)
    return receipt


def derived_from_receipt(receipt: dict, derived_data: Path | None) -> Path:
    name = receipt.get("path")
    if (not isinstance(name, str) or not re.fullmatch(r"iteration-trace-config-[0-9a-f]{24}\.xctestrun", name)
            or receipt.get("archive") != "iteration-trace-config.xctestrun"):
        raise HandshakeError("Invalid retained trace configuration identity")
    if derived_data is None:
        return Path(name)
    return derived_data / "Build/Products" / name


def prepare_test_run(derived_data: Path, control: Path, revision: str, iteration: int,
                     run_directory: Path | None = None, build_provenance: dict | None = None,
                     target_probe_files: tuple[Path, ...] = ()):
    if run_directory is None or build_provenance is None:
        raise HandshakeError("Each trace configuration requires a new run directory and validated build provenance")
    if not re.fullmatch(r"[0-9a-f]{40}", revision) or iteration not in range(30):
        raise HandshakeError("Trace configuration requires an exact source revision and iteration in 0..29")
    if (build_provenance.get("path") != derived_data / BUILD_PROVENANCE_NAME
            or build_provenance.get("source_revision") != revision):
        raise HandshakeError("Validated build provenance must match this exact revision and DerivedData")
    if not control.is_dir() or control.is_symlink() or control.parent != run_directory:
        raise HandshakeError("Trace control must be a real directory inside its own run directory")
    if target_probe_files:
        expected_probes = tuple(run_directory / name for name in TARGET_PROBE_FILENAMES)
        if (target_probe_files != expected_probes
                or any(not path.is_file() or path.is_symlink() for path in target_probe_files)):
            raise HandshakeError("Current target probes must be ordinary files generated in this run directory")
    unexpected = [path for path in run_directory.iterdir() if path not in {control, *target_probe_files}]
    if (not run_directory.is_dir() or run_directory.is_symlink() or unexpected
            or any(control.iterdir()) or (run_directory / "iteration-trace-config.xctestrun").exists()):
        raise HandshakeError("Trace configuration requires a new run directory containing only an empty control")
    # Keep __TESTROOT__ resolution in Build/Products. Include the new control
    # directory's full name and retain the final bytes beside the iteration receipt.
    source = original_test_run(derived_data, build_provenance)
    identity = hashlib.sha256(f"{revision}\0{control}\0{iteration}".encode()).hexdigest()[:24]
    destination = source.with_name(f"iteration-trace-config-{identity}.xctestrun")
    if destination.exists() or destination.is_symlink():
        raise HandshakeError("Refusing to replace an existing trace configuration")
    with tempfile.TemporaryDirectory(prefix=".iteration-trace-prepare-", dir=destination.parent) as temporary:
        converted = Path(temporary) / destination.name
        subprocess.run(["plutil", "-convert", "binary1", "-o", str(converted), "--", str(source)], check=True)
        values = {"REFRACT_BENCH_REVISION": revision,
                  "REFRACT_BENCH_TRACE_CONTROL": str(control),
                  "REFRACT_BENCH_TRACE_ITERATION": str(iteration)}
        for name, value in values.items():
            subprocess.run(["plutil", "-replace",
                            f"RefractBenchUITests.TestingEnvironmentVariables.{name}",
                            "-string", value, str(converted)], check=True)
        checksum = file_sha256(converted)
        checked_trace_environment(converted, values)
        try:
            os.link(converted, destination)
        except FileExistsError as error:
            raise HandshakeError("Refusing to replace an existing trace configuration") from error
        archived = run_directory / "iteration-trace-config.xctestrun"
        with archived.open("xb") as archive_stream:
            archive_stream.write(bounded_file_bytes(converted))
        if file_sha256(archived) != checksum:
            raise HandshakeError("Archived trace configuration does not match its executed bytes")
        with (run_directory / BUILD_PROVENANCE_NAME).open("xb") as archive_stream:
            archive_stream.write(bounded_file_bytes(build_provenance["path"]))
        archived_manifest = run_directory / BUILD_PROVENANCE_NAME
        if (archived_manifest.is_symlink()
                or file_sha256(archived_manifest) != file_sha256(build_provenance["path"])):
            raise HandshakeError("Archived build provenance does not match the validated build")
        atomic_json(run_directory / "iteration-trace-config.json", {
            "schema": 1, "path": destination.name, "archive": archived.name,
            "configuration_sha256": checksum,
            "build_provenance_sha256": file_sha256(build_provenance["path"]),
            "source_xctestrun": source.name, "source_revision": revision,
            "control_directory": str(control), "iteration": iteration,
        })
        validate_trace_configuration(run_directory, revision, control, iteration, derived_data)
    return destination


def saved_trace_matches(saved: str, requested: Path) -> bool:
    """xctrace may print a bare package name even when --output was absolute."""
    path = Path(saved.strip())
    return path == requested or (path.parent == Path(".") and path.name == requested.name)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-directory", required=True, type=Path, help="A new directory for one iteration")
    parser.add_argument("--derived-data", required=True, type=Path, help="Existing build-for-testing output")
    parser.add_argument("--target-udid", required=True, help="An explicitly owned already-running target")
    parser.add_argument("--target-metadata", type=Path,
                        help="Optional existing read-only probe_target.py output")
    parser.add_argument("--variant", required=True, choices=VARIANTS)
    parser.add_argument("--scenario", required=True, choices=SCENARIOS)
    parser.add_argument("--iteration", required=True, type=int)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--template", default="Animation Hitches",
                        help="Explicit Instruments template supported by the selected target")
    parser.add_argument("--readiness-timeout", type=float, default=60)
    parser.add_argument("--completion-timeout", type=float, default=180)
    args = parser.parse_args(argv)
    run = args.run_directory
    log = run / "xcodebuild.log"
    process = None
    try:
        if args.source_revision != subprocess.check_output(
                ["git", "-C", str(Path(__file__).resolve().parents[2]), "rev-parse", "HEAD"], text=True).strip():
            raise HandshakeError("The requested source revision is not the current committed HEAD")
        if subprocess.check_output(["git", "-C", str(Path(__file__).resolve().parents[2]),
                                    "status", "--porcelain"], text=True):
            raise HandshakeError("Timing requires a clean committed source revision")
        run.mkdir(parents=True, exist_ok=False)
        target_path = args.target_metadata
        target_probe_files: tuple[Path, ...] = ()
        if args.target_metadata is None:
            target_probe_files = tuple(run / name for name in TARGET_PROBE_FILENAMES)
            target_path = run / "target.json"
            # Both probes are read-only. They never create, boot, restart, erase,
            # pair or choose a target; the caller owns its exclusive lifecycle.
            subprocess.run(["xcrun", "devicectl", "list", "devices", "--json-output",
                            str(run / "targets.json"), "--quiet"], check=True)
            with (run / "simulators.json").open("x", encoding="utf-8") as stream:
                subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"],
                               stdout=stream, check=True)
            subprocess.run([sys.executable, "-I", str(Path(__file__).resolve().parent / "probe_target.py"),
                            "--udid", args.target_udid, "--include-udid", "--simulators", str(run / "simulators.json"),
                            "--targets", str(run / "targets.json"), "--output", str(target_path)], check=True)
        target = read_json(target_path)
        if target.get("target_label") != "SIMULATOR" or target.get("device_result") is not False:
            raise HandshakeError("The target probe must explicitly label a simulator, not a device result")
        if target.get("udid") != args.target_udid:
            raise HandshakeError("The read-only target probe does not match the explicit target UDID")
        control = run / "control"
        control.mkdir()
        # XCTest is the only app launcher. It remains blocked until the recorder
        # acknowledgement is durable. This test command never manages a target.
        test = traced_test_name(args.variant, args.scenario)
        environment = dict(os.environ, REFRACT_BENCH_REVISION=args.source_revision,
                           REFRACT_BENCH_TRACE_CONTROL=str(control),
                           REFRACT_BENCH_TRACE_ITERATION=str(args.iteration))
        build_provenance = validate_build_provenance(args.derived_data, args.source_revision)
        test_run = prepare_test_run(args.derived_data, control, args.source_revision, args.iteration,
                                    run, build_provenance, target_probe_files)
        validate_trace_configuration(run, args.source_revision, control, args.iteration, args.derived_data)
        with log.open("x", encoding="utf-8") as stream:
            validate_build_provenance(args.derived_data, args.source_revision)
            process = subprocess.Popen(
                test_command(test_run, args.target_udid, test, args.source_revision, run / "results.xcresult"),
                env=environment, stdout=stream, stderr=subprocess.STDOUT)
            session = Session(target=args.target_udid, variant=args.variant, scenario=args.scenario,
                              iteration=args.iteration, revision=args.source_revision, run_directory=run,
                              xcodebuild_log=log, control_directory=control,
                              readiness_timeout=args.readiness_timeout,
                              completion_timeout=args.completion_timeout, template=args.template,
                              derived_data=args.derived_data, target_probe_files=target_probe_files)
            result = session.capture(process)
            status = process.wait(timeout=args.completion_timeout)
            if status != 0:
                raise HandshakeError(f"Xcode test failed with status {status}; captured trace is not passing evidence")
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (HandshakeError, ArchiveError, OSError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired) as error:
        print(f"iteration-trace: ERROR: {error}", file=sys.stderr)
        return 2
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


if __name__ == "__main__":
    sys.exit(main())
