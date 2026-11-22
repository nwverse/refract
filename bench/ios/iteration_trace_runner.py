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
import os
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from archive_trace import ArchiveError, archive_trace


class HandshakeError(ValueError):
    pass


VARIANTS = ("generated", "reference")
SCENARIOS = ("scroll", "stateUpdate")
READY_OUTPUT = re.compile(r"(?:^|\n)Starting recording with the (.+?) template\.[^\n]*(?:\n|$)")
SAVED_OUTPUT = re.compile(r"(?:^|\n)Output (?:file saved as|saved): (.+?)\s*(?:\n|$)")


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


def read_json(path: Path) -> dict:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise HandshakeError(f"Cannot read handshake {path.name}: {error}") from error
    if not isinstance(payload, dict):
        raise HandshakeError(f"Handshake {path.name} must be a JSON object")
    return payload


def checked_identity(packet: dict, session: "Session") -> None:
    expected = {
        "schema": 1,
        "session": session.session_id,
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


class Session:
    """One non-reusable variant/scenario/iteration/recorder binding."""

    def __init__(self, *, target: str, variant: str, scenario: str, iteration: int,
                 revision: str, run_directory: Path, xcodebuild_log: Path,
                 control_directory: Path, readiness_timeout: float = 60,
                 completion_timeout: float = 180, window: str = "5s",
                 template: str = "Animation Hitches", session_id: int = 1,
                 target_label: str = "SIMULATOR"):
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
        self.raw = run_directory / "raw"
        self.identity = f"{variant}-{scenario}-{iteration}"
        self.trace = run_directory / f"{self.identity}.trace"
        self.archive = self.raw / f"{self.identity}.trace.zip"

    def capture(self, test_process: subprocess.Popen, recorder_factory=None) -> dict:
        if self.run_directory.exists() and any(self.run_directory.iterdir()):
            # The caller creates a new run directory for the test log and empty
            # control directory before capture; nothing else may already exist.
            # The ordinary CLI writes these three fresh read-only target probes
            # before capture. No other pre-existing content is evidence-safe.
            allowed = {self.xcodebuild_log, self.control_directory,
                       *(self.run_directory / name for name in
                         ("targets.json", "simulators.json", "target.json"))}
            unexpected = [p for p in self.run_directory.iterdir() if p not in allowed]
            if unexpected or not self.xcodebuild_log.is_file():
                raise HandshakeError("A new run directory contains unexpected or stale files")
        if not self.xcodebuild_log.is_file():
            raise HandshakeError("The current xcodebuild log is missing")
        self.control_directory.mkdir(parents=True, exist_ok=True)
        if any(self.control_directory.iterdir()):
            raise HandshakeError("Refusing a reused or stale control directory")
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
            # Accessibility reports this launch's native completion count (one),
            # not a cumulative count from the retired single-launch task.
            expected_completion = f"{self.variant} {self.scenario} complete 1"
            if completion.get("completion") != expected_completion or completion.get("pid") != pid:
                raise HandshakeError("The native completion or PID does not match this iteration")
            # XCTest may return as soon as the app terminates. Its final exit
            # status is checked by main after this recorder is fully stopped.
            atomic_json(self.raw / "completion.json", completion)

            # Ask only our xctrace child to stop gracefully (SIGINT is the
            # Instruments interrupt path), flush its package, then release XCTest.
            atomic_json(self.control_directory / "recorder-stop", {"session": self.session_id})
            recorder.send_signal(signal.SIGINT)
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
            if len(saved) != 1 or Path(saved[0].strip()) != self.trace:
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


def traced_test_name(variant: str, scenario: str) -> str:
    """Return the existing Swift XCTest selector without changing its camel case."""
    selector = {"scroll": "Scroll", "stateUpdate": "StateUpdate"}[scenario]
    return f"RefractBenchUITests/RefractBenchUITests/test{variant.capitalize()}{selector}Trace"


def test_command(test_run: Path, target_udid: str, test: str, revision: str,
                 results: Path) -> list[str]:
    return ["xcodebuild", "test-without-building", "-xctestrun", str(test_run),
            "-resultBundlePath", str(results), "-destination", f"platform=iOS Simulator,id={target_udid}",
            f"-only-testing:{test}", "CODE_SIGNING_ALLOWED=NO", f"REFRACT_BENCH_REVISION={revision}"]


def prepare_test_run(derived_data: Path, control: Path, revision: str, iteration: int) -> Path:
    # An xctestrun resolves __TESTROOT__ from its containing Build/Products
    # directory; copying it elsewhere changes the native test product paths.
    sources = sorted((derived_data / "Build/Products").glob("*.xctestrun"))
    if len(sources) != 1:
        raise HandshakeError("Exactly one generated xctestrun file is required")
    destination = sources[0].with_name("iteration-trace-config.xctestrun")
    subprocess.run(["plutil", "-convert", "binary1", "-o", str(destination), "--", str(sources[0])], check=True)
    values = {"REFRACT_BENCH_REVISION": revision,
              "REFRACT_BENCH_TRACE_CONTROL": str(control),
              "REFRACT_BENCH_TRACE_ITERATION": str(iteration)}
    for name, value in values.items():
        subprocess.run(["plutil", "-replace",
                        f"RefractBenchUITests.TestingEnvironmentVariables.{name}",
                        "-string", value, str(destination)], check=True)
    return destination


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
        if args.target_metadata is None:
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
        test_run = prepare_test_run(args.derived_data, control, args.source_revision, args.iteration)
        with log.open("x", encoding="utf-8") as stream:
            process = subprocess.Popen(
                test_command(test_run, args.target_udid, test, args.source_revision, run / "results.xcresult"),
                env=environment, stdout=stream, stderr=subprocess.STDOUT)
            session = Session(target=args.target_udid, variant=args.variant, scenario=args.scenario,
                              iteration=args.iteration, revision=args.source_revision, run_directory=run,
                              xcodebuild_log=log, control_directory=control,
                              readiness_timeout=args.readiness_timeout,
                              completion_timeout=args.completion_timeout, template=args.template)
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
