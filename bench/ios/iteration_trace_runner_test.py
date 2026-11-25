#!/usr/bin/env python3
"""Synthetic lifecycle tests; no target, Xcode or Instruments is invoked."""

from __future__ import annotations

import hashlib
import io
import json
import os
import plistlib
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from archive_trace import ArchiveError
from iteration_trace_runner import (SAVED_OUTPUT, TARGET_PROBE_FILENAMES, HandshakeError, Session,
                                    checked_final_samples, main, original_test_run, prepare_test_run,
                                    record_build_provenance, saved_trace_matches, test_command, traced_test_name,
                                    validate_build_provenance, validate_trace_configuration)
import iteration_trace_runner as runner
sys.path.insert(0, str(HERE.parent / "common"))
from paired_report import EvidenceError, make_report
from report_test import PairedReportTest

PAIRED_REPORTER_FIXTURE = (PairedReportTest,)
# A tuple keeps the helper out of unittest's module-level TestCase discovery.
del PairedReportTest


def synthetic_final_samples(**changes):
    samples = {
        "schema": 1, "session": 1, "sourceRevision": "a" * 40,
        "variant": "generated", "scenario": "scroll", "iteration": 2, "pid": 4242,
        "completedIterations": 1, "recordedIteration": 2,
        "frameIntervalMs": [16.666666666666668, 16.5, 16.75],
        "iterationByFrame": [2, 2, 2],
    }
    samples.update(changes)
    return samples


class RecorderFixture:
    """Separate fake XCTest and xctrace processes with observable commands."""

    def __init__(self, root: Path, create_run_directory: bool = True):
        self.root = root
        self.work = root.parent / f"{root.name}-synthetic-tools"
        self.work.mkdir(exist_ok=True)
        self.commands = self.work / "commands.jsonl"
        self.process = None
        self.recorder = None
        self.cleanup = lambda: None
        self.output = root / "xcodebuild.log"
        if create_run_directory:
            root.mkdir(exist_ok=True)
            (root / "control").mkdir(exist_ok=True)

    def start(self, preflight=None, session=None, **kwargs):
        # Mirror the real launch order: freeze the fresh control epoch before
        # the synthetic XCTest process is spawned. Callers that exercise the
        # runner protocol pass a preflight callback (typically
        # session.record_capture_start_epoch); negative fixtures that inject
        # pre-existing packets skip preflight on purpose.
        if preflight is None and session is not None:
            preflight = session.record_capture_start_epoch
        if preflight is not None:
            preflight()
        self.prepare(**kwargs)
        self.output.write_text("native XCTApplicationLaunchMetric remains unchanged\n", encoding="utf-8")

    def prepare(self, ready: str | None = "Starting recording with the Animation Hitches template. Attach to stop.",
                completion: str = "generated scroll complete 1", pid: int | None = 4242,
                session: int = 1, duplicate_completion: bool = False, duplicate_request: bool = False,
                recorder_after_ready_exit: int = 0, ready_delay: float = 0,
                write_trace: bool = True, process_state: str = "running",
                missing_completion: bool = False, app_iteration: int = 2,
                saved_path: str | None = None, recorder_stop_status: int = 0,
                completion_delay: float = 0, app_revision: str | None = None,
                app_scenario: str = "scroll",
                saved_spelling: str = "Output saved", saved_lines: int = 1, missing_begin: bool = False,
                final_samples: dict | None | str = "default",
                stale_periodic_plist: bool = False, duplicate_native_completion: bool = False,
                native_samples: dict | None | str = "default"):
        if final_samples == "default":
            final_samples = synthetic_final_samples(iteration=app_iteration, recordedIteration=app_iteration,
                                                    scenario=app_scenario, iterationByFrame=[app_iteration] * 3,
                                                    sourceRevision=app_revision or "a" * 40)
        if native_samples == "default":
            native_samples = final_samples
        stale_plist = {"completedIterations": 0, "recordedIteration": 0,
                       "frameIntervalMs": [16.5] * 60, "iterationByFrame": [app_iteration] * 60}
        app_script = self.work / "fake_xcodebuild.py"
        app_script.write_text(f'''import json, pathlib, plistlib, sys, time
control = pathlib.Path(sys.argv[1])
def publish(name, value):
    temporary = control / ('.' + name + '.tmp')
    temporary.write_text(json.dumps(value))
    temporary.rename(control / name)
packet = {{"schema": 1, "session": {session}, "revision": {app_revision or ("a" * 40)!r},
          "variant": "generated", "scenario": {app_scenario!r}, "iteration": {app_iteration},
          "pid": {pid!r}, "process": {process_state!r}, "state": "ready"}}
time.sleep(0.02)
(control / "request.json").write_text(json.dumps(packet))
if {duplicate_request!r}:
    (control / "request-2.json").write_text(json.dumps(dict(packet, pid=4243)))
while not (control / "recorder-ready.json").exists():
    time.sleep(0.01)
time.sleep({completion_delay!r})
packet["state"] = "complete"
packet["completion"] = {completion!r}
packet["finalSamples"] = json.loads({json.dumps(final_samples)!r})
begin = dict(packet, state="begin")
if not {missing_begin!r}:
    publish("begin.json", begin)
    native = dict(packet, finalSamples=json.loads({json.dumps(native_samples)!r}))
    publish("native-completion.json", native)
if {duplicate_native_completion!r}:
    (control / "native-completion-2.json").write_text(json.dumps(packet))
if {stale_periodic_plist!r}:
    (control / "diagnostic.plist").write_bytes(plistlib.dumps({{**packet, **{stale_plist!r}}}))
if not {missing_completion!r}:
    publish("completion.json", packet)
if {duplicate_completion!r}:
    (control / "completion-2.json").write_text(json.dumps(packet))
while not (control / "recorder-finished.json").exists():
    time.sleep(0.01)
''')
        recorder_script = self.work / "fake_xcrun.py"
        recorder_script.write_text(f'''import json, os, pathlib, signal, sys, time
with open(os.environ["REFRACT_SYNTHETIC_XCRUN"], "a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\\n")
output = sys.argv[sys.argv.index("--output") + 1]
control = pathlib.Path(sys.argv[sys.argv.index("--control-directory") + 1])
def finish(status):
    if {write_trace!r}:
        trace = pathlib.Path(output)
        (trace / "Data").mkdir(parents=True, exist_ok=True)
        (trace / "Data" / "samples.bin").write_bytes(b"synthetic package member")
        for _ in range({saved_lines!r}):
            print({saved_spelling!r} + ": " + ({saved_path!r} or output), flush=True)
    os._exit(status)
signal.signal(signal.SIGINT, lambda *_: finish(0))
signal.signal(signal.SIGTERM, lambda *_: finish(143))
import json, os, pathlib, time

if {ready!r} is None:
    sys.exit(7)
print({ready!r}.format(trace=output), flush=True)
if {recorder_after_ready_exit!r}:
    while not (control / "recorder-ready.json").exists():
        time.sleep(0.001)
    sys.exit({recorder_after_ready_exit!r})
time.sleep({completion_delay!r})
if {recorder_stop_status!r}:
    while not (control / "completion.json").exists():
        time.sleep(0.001)
    sys.exit({recorder_stop_status!r})
if {write_trace!r}:
    trace = pathlib.Path(output)
    (trace / "Data").mkdir(parents=True, exist_ok=True)
    (trace / "Data" / "samples.bin").write_bytes(b"synthetic package member")
while not (control / "recorder-stop").exists():
    time.sleep(0.01)
''')
        self.process = subprocess.Popen(
            ["python3", "-I", str(app_script), str(self.root / "control")],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        def factory(command, log):
            environment = dict(os.environ, REFRACT_SYNTHETIC_XCRUN=str(self.commands))
            self.recorder = subprocess.Popen(
                ["python3", "-I", str(recorder_script), *command,
                 "--control-directory", str(self.root / "control")],
                env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            return self.recorder
        self.recorder_factory = factory

        def stop():
            for process in (self.process, self.recorder):
                if process is None:
                    continue
                if process.poll() is None:
                    process.terminate()
                try:
                    process.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.communicate(timeout=5)
        self.cleanup = stop

    def stop(self):
        self.cleanup()


class StopRaceRecorder:
    def __init__(self, control, stop_poll, send_error=None,
                 stdout="Starting recording with the Animation Hitches template. Attach to stop.\n"):
        self.pid = 4243
        self.control = control
        self.stop_poll = stop_poll
        self.returncode = None
        self.stdout = io.StringIO(stdout)
        self.send_error = send_error
        self.signals = []

    def poll(self):
        if (self.control / "recorder-stop").exists():
            self.returncode = self.stop_poll
        return self.returncode

    def send_signal(self, signal_number):
        self.signals.append(signal_number)
        if self.send_error is not None:
            raise self.send_error

    def wait(self, timeout):
        self.returncode = 7
        return 7

    def terminate(self):
        self.returncode = -15

    def communicate(self, timeout):
        return "", ""


class IterationTraceRunnerTest(unittest.TestCase):
    def write_synthetic_configuration(self, run, revision, control, iteration):
        derived_data = run.parent / f"{run.name}-derived-data"
        values = {"REFRACT_BENCH_REVISION": revision, "REFRACT_BENCH_TRACE_CONTROL": str(control),
                  "REFRACT_BENCH_TRACE_ITERATION": str(iteration)}
        destination = derived_data / "Build/Products/iteration-trace-config-0123456789abcdef01234567.xctestrun"
        destination.parent.mkdir(parents=True, exist_ok=True)
        (derived_data / "Build/Products/RefractBench.xctestrun").write_bytes(
            b"synthetic original xctestrun")
        destination.write_bytes(plistlib.dumps({"RefractBenchUITests": {"TestingEnvironmentVariables": values}}))
        configuration = run / "iteration-trace-config.xctestrun"
        configuration.write_bytes(destination.read_bytes())
        manifest = run / "refract-build-provenance.json"
        manifest.write_bytes(b'{"synthetic": "provenance"}\n')
        receipt = {"schema": 1, "path": destination.name, "archive": configuration.name,
                   "configuration_sha256": hashlib.sha256(configuration.read_bytes()).hexdigest(),
                   "build_provenance_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
                   "source_revision": revision, "control_directory": str(control), "iteration": iteration}
        (run / "iteration-trace-config.json").write_text(json.dumps(receipt))
        products = derived_data / "Build/Products/Release-iphonesimulator"
        test_bundle = products / "RefractBenchUITests-Runner.app/PlugIns/RefractBenchUITests.xctest"
        test_bundle.mkdir(parents=True, exist_ok=True)
        for bundle, executable in ((products / "RefractBench.app", "RefractBench"),
                                   (products / "RefractBenchUITests-Runner.app", "RefractBenchUITests-Runner"),
                                   (test_bundle, "RefractBenchUITests")):
            bundle.mkdir(exist_ok=True)
            (bundle / executable).write_bytes(b"synthetic build product")
            (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": executable}))
        if not (derived_data / "refract-build-provenance.json").exists():
            record_build_provenance(derived_data, revision)
        return derived_data, destination

    def read_synthetic_environment(self, command, check, capture_output, text):
        values = plistlib.loads(Path(command[-1]).read_bytes())
        values = values["RefractBenchUITests"]["TestingEnvironmentVariables"]
        return subprocess.CompletedProcess(command, 0, json.dumps(values), "")

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.recorder = RecorderFixture(self.root)
        self.addCleanup(lambda: self.recorder.stop())
        self.environment = dict(os.environ, TARGET_UDID="synthetic-target")
        self.trace = self.root / "generated-scroll-2.trace"

    def session(self, start=False, **kwargs):
        values = dict(target="synthetic-target", variant="generated", scenario="scroll", iteration=2,
                      revision="a" * 40, run_directory=self.root, xcodebuild_log=self.recorder.output,
                      control_directory=self.root / "control", readiness_timeout=0.5, completion_timeout=0.5)
        values.update(kwargs)
        derived_data = kwargs.get("derived_data")
        if derived_data is None:
            derived_data, destination = self.write_synthetic_configuration(
                values["run_directory"], values["revision"], values["control_directory"], values["iteration"])
            values["derived_data"] = derived_data
        session = Session(**values)
        if start:
            self.recorder.start(session=session)
        return session

    def capture(self, session, fixture=None):
        fixture = fixture or self.recorder
        if getattr(session, "_capture_epoch", None) is None:
            # A direct synthetic Session has no real main() preflight. Freeze
            # before invoking capture, not after the packet checks, mirroring
            # the explicit launch boundary used by the real CLI.
            session.record_capture_start_epoch()
        with mock.patch("iteration_trace_runner.subprocess.run", side_effect=self.read_synthetic_environment):
            return session.capture(fixture.process, fixture.recorder_factory)

    def launch(self, session=None, fixture=None, session_kwargs=None, **recorder_kwargs):
        """Mirror main(): preflight the fresh control epoch before launching
        the synthetic XCTest process. Callers may pass an explicit Session
        (e.g. to inject variant/scenario overrides) or session_kwargs for the
        default Session factory. Returns the Session for self.capture."""
        fixture = fixture or self.recorder
        session = session or self.session(**(session_kwargs or {}))
        fixture.start(preflight=session.record_capture_start_epoch, **recorder_kwargs)
        return session

    def run_success(self):
        session = self.launch()
        result = self.capture(session)
        self.recorder.process.wait(timeout=5)
        return result

    def test_ready_precedes_work_and_exact_package_is_archived(self):
        result = self.run_success()
        self.assertEqual(result["status"], "complete")
        self.assertEqual(result["pid"], 4242)
        self.assertEqual(result["target_udid"], "synthetic-target")
        self.assertEqual(result["target_label"], "SIMULATOR")
        self.assertFalse(result["device_result"])
        self.assertEqual(result["source_revision"], "a" * 40)
        self.assertEqual(result["trace"], "raw/generated-scroll-2.trace.zip")
        archive = self.root / result["trace"]
        self.assertTrue(archive.is_file())
        self.assertEqual(result["bytes"], archive.stat().st_size)
        self.assertEqual(len(result["sha256"]), 64)
        self.assertIn("XCTApplicationLaunchMetric", self.recorder.output.read_text())
        command = self.recorder.commands.read_text()
        arguments = json.loads(command.splitlines()[0])
        self.assertEqual(arguments[arguments.index("--attach") + 1], "4242")
        self.assertEqual(arguments[arguments.index("--output") + 1], str(self.trace))
        self.assertIn('"record"', command)
        self.assertIn('"--attach", "4242"', command)
        self.assertIn('"--window", "5s"', command)
        self.assertNotIn('"boot"', command)
        self.assertNotIn('"shutdown"', command)
        self.assertFalse((self.root / "raw/generated-scroll-2.trace").exists())
        self.assertTrue((self.root / "raw/recorder-ready.json").is_file())
        self.assertTrue((self.root / "raw/completion.json").is_file())
        self.assertTrue((self.root / "raw/recorder.log").is_file())
        self.assertTrue((self.root / "xcodebuild.log").is_file())
        self.assertTrue((self.root / "raw/recorder-finished.json").is_file())
        self.assertEqual(result["archived_package_name"], "generated-scroll-2.trace")
        self.assertEqual(result["native_samples"]["path"], "raw/native-samples.json")
        archived_samples = json.loads((self.root / result["native_samples"]["path"]).read_text())
        self.assertEqual(archived_samples, synthetic_final_samples())
        self.assertEqual(result["native_samples"]["sha256"], hashlib.sha256(
            (self.root / "raw/native-samples.json").read_bytes()).hexdigest())

    def test_stale_periodic_plist_cannot_override_the_valid_final_packet(self):
        self.recorder.start(session=self.session(), stale_periodic_plist=True)
        result = self.capture(self.session())
        self.recorder.process.wait(timeout=5)
        plist = plistlib.loads((self.root / "control/diagnostic.plist").read_bytes())
        self.assertEqual(plist["completedIterations"], 0)
        self.assertEqual(plist["recordedIteration"], 0)
        self.assertEqual(len(plist["frameIntervalMs"]), 60)
        samples = json.loads((self.root / result["native_samples"]["path"]).read_text())
        self.assertEqual(samples["completedIterations"], 1)
        self.assertEqual(samples["recordedIteration"], 2)
        self.assertEqual(len(samples["frameIntervalMs"]), 3)
        self.assertEqual(result["status"], "complete")

    def test_final_sample_identity_and_finite_intervals_fail_closed(self):
        session = mock.Mock(session_id=1, revision="a" * 40, variant="generated", scenario="scroll", iteration=2)
        valid = synthetic_final_samples()
        self.assertEqual(checked_final_samples({"finalSamples": valid}, session, 4242), valid)
        invalid = [
            synthetic_final_samples(sourceRevision="b" * 40),
            synthetic_final_samples(session=2), synthetic_final_samples(pid=4243),
            synthetic_final_samples(variant="reference"), synthetic_final_samples(scenario="stateUpdate"),
            synthetic_final_samples(iteration=30), synthetic_final_samples(recordedIteration=30),
            synthetic_final_samples(completedIterations=0), synthetic_final_samples(completedIterations=2),
            synthetic_final_samples(frameIntervalMs=[]),
            synthetic_final_samples(frameIntervalMs=[16.5, float("nan")]),
            synthetic_final_samples(frameIntervalMs=[16.5, 10**400]),
            synthetic_final_samples(frameIntervalMs=[16.5, float("inf")]),
            synthetic_final_samples(frameIntervalMs=[16.5, -1]),
            synthetic_final_samples(frameIntervalMs=[16.5, True]),
            synthetic_final_samples(iterationByFrame=[2, 1, 2]),
            synthetic_final_samples(iterationByFrame=[2, 2]),
            synthetic_final_samples(iterationByFrame=[2, False, 2]),
        ]
        for samples in invalid:
            with self.subTest(samples=samples):
                with self.assertRaisesRegex(HandshakeError, "sample|frame|display|interval"):
                    checked_final_samples({"finalSamples": samples}, session, 4242)

    def test_native_packet_and_forwarded_samples_must_be_identical(self):
        self.recorder.start(session=self.session(), native_samples=synthetic_final_samples(frameIntervalMs=[16.5, 16.5, 16.5]))
        with self.assertRaisesRegex(HandshakeError, "exact native final sample"):
            self.capture(self.session())
        self.assertFalse((self.root / "raw/native-samples.json").exists())
        self.assertFalse((self.root / "raw/generated-scroll-2.trace.zip").exists())

    def test_missing_partial_stale_and_ambiguous_final_packets_reject_before_archive(self):
        missing_keys = tuple(synthetic_final_samples())
        cases = [("missing", None), ("duplicate", "duplicate")]
        cases.extend((f"partial-{key}", {key: None}) for key in missing_keys)
        cases.extend([
            ("stale-revision", {"sourceRevision": "b" * 40}),
            ("stale-completion", {"completedIterations": 0}),
            ("wrong-iteration", {"recordedIteration": 30}),
            ("wrong-frame-tag", {"iterationByFrame": [2, 1, 2]}),
            ("nonfinite", {"frameIntervalMs": [16.5, float("inf"), 16.5]}),
        ])
        for name, change in cases:
            with self.subTest(name=name):
                root = self.root / f"final-samples-{name}"
                root.mkdir()
                recorder = RecorderFixture(root)
                self.addCleanup(recorder.stop)
                session = self.session(run_directory=root, xcodebuild_log=recorder.output,
                                       control_directory=root / "control")
                if change == "duplicate":
                    recorder.start(session=session, duplicate_native_completion=True)
                elif change is None:
                    recorder.start(session=session, final_samples=None)
                else:
                    recorder.start(session=session, final_samples=synthetic_final_samples(**change))
                with self.assertRaisesRegex(HandshakeError, "sample|frame|display|interval|Ambiguous"):
                    self.capture(session, recorder)
                self.assertFalse((root / "raw/generated-scroll-2.trace.zip").exists())
                self.assertFalse((root / "raw/native-samples.json").exists())
                self.assertFalse((root / "raw/iteration-trace.json").exists())

    def test_current_target_probe_files_require_explicit_current_run_admission(self):
        for name in TARGET_PROBE_FILENAMES:
            (self.root / name).write_text('{"current_probe": true}\n')
        # First call: probes present but not admitted by the Session -> the
        # run-directory preflight rejects them before any packet arrives.
        session = self.launch()
        with self.assertRaisesRegex(HandshakeError, "unexpected or stale"):
            self.capture(session)
        self.assertFalse((self.root / "raw").exists())
        self.assertFalse(self.recorder.commands.exists())

        # Second call: probes are explicitly admitted for this run.
        probes = tuple(self.root / name for name in TARGET_PROBE_FILENAMES)
        admitted = self.session(target_probe_files=probes)
        admitted.record_capture_start_epoch()
        result = self.capture(admitted)
        self.assertEqual(result["status"], "complete")
        self.recorder.process.wait(timeout=5)

    def test_unexpected_files_are_rejected_with_current_target_probes(self):
        probes = tuple(self.root / name for name in TARGET_PROBE_FILENAMES)
        for path in probes:
            path.write_text('{"current_probe": true}\n')
        unexpected = self.root / "unexpected.json"
        unexpected.write_text("stale evidence\n")
        session = self.launch(session_kwargs={"target_probe_files": probes})
        with self.assertRaisesRegex(HandshakeError, "unexpected or stale"):
            self.capture(session)
        self.assertEqual(unexpected.read_text(), "stale evidence\n")
        self.assertFalse((self.root / "raw").exists())
        self.assertFalse(self.recorder.commands.exists())

    def test_ordinary_cli_admits_only_the_probes_it_generated(self):
        self.recorder.stop()
        self.root = self.root / "current-cli-run"
        self.recorder = RecorderFixture(self.root, create_run_directory=False)
        self.addCleanup(self.recorder.stop)
        derived_data = self.root.parent / "DerivedData"
        products = derived_data / "Build/Products/Release-iphonesimulator"
        test_bundle = products / "RefractBenchUITests-Runner.app/PlugIns/RefractBenchUITests.xctest"
        test_bundle.mkdir(parents=True, exist_ok=True)
        for bundle, executable in ((products / "RefractBench.app", "RefractBench"),
                                   (products / "RefractBenchUITests-Runner.app", "RefractBenchUITests-Runner"),
                                   (test_bundle, "RefractBenchUITests")):
            bundle.mkdir(exist_ok=True)
            (bundle / executable).write_bytes(b"synthetic build product")
            (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": executable}))
        original = derived_data / "Build/Products/RefractBench.xctestrun"
        original_bytes = plistlib.dumps({"RefractBenchUITests": {"TestingEnvironmentVariables": {
            "PRODUCT_MODULE_NAME": "RefractBenchUITests", "XCODE_SCHEME_NAME": "RefractBench",
            "DYLD_LIBRARY_PATH": "__TESTROOT__/Release-iphonesimulator",
        }}})
        original.write_bytes(original_bytes)
        runner.record_build_provenance(derived_data, "a" * 40)
        configured = {}

        def run(command, **kwargs):
            self.assertTrue(kwargs.get("check", False))
            if command[0] == "plutil":
                if command[1:3] == ["-convert", "binary1"]:
                    Path(command[4]).write_bytes(plistlib.dumps(
                        plistlib.loads(Path(command[6]).read_bytes()), fmt=plistlib.FMT_BINARY))
                elif command[1] == "-extract":
                    environment = plistlib.loads(Path(command[-1]).read_bytes())[
                        "RefractBenchUITests"]["TestingEnvironmentVariables"]
                    configured.update(environment)
                    return subprocess.CompletedProcess(command, 0, json.dumps(environment), "")
                else:
                    prefix = "RefractBenchUITests.TestingEnvironmentVariables."
                    self.assertTrue(command[2].startswith(prefix))
                    destination = Path(command[-1])
                    value = plistlib.loads(destination.read_bytes())
                    value["RefractBenchUITests"]["TestingEnvironmentVariables"][
                        command[2][len(prefix):]] = command[4]
                    destination.write_bytes(plistlib.dumps(value, fmt=plistlib.FMT_BINARY))
            elif "devicectl" in command:
                (self.root / "targets.json").write_text('{"devices": []}\n')
            elif "simctl" in command:
                kwargs["stdout"].write('{"devices": {}}\n')
            elif command[1:3] == ["-I", str(HERE / "probe_target.py")]:
                (self.root / "target.json").write_text(json.dumps({
                    "target_label": "SIMULATOR", "device_result": False, "udid": "synthetic-target",
                }) + "\n")
            return subprocess.CompletedProcess(command, 0)

        original_popen = subprocess.Popen

        def popen(command, **kwargs):
            if command[0] == "xcodebuild":
                # main() has created and preflighted the fresh control epoch
                # before reaching Popen; only now may the fake XCTest publish.
                self.recorder.prepare()
                return self.recorder.process
            return original_popen(command, **kwargs)

        original_capture = Session.capture

        def capture(session, process):
            self.assertEqual(session.target_probe_files,
                             tuple(self.root / name for name in TARGET_PROBE_FILENAMES))
            return original_capture(session, process, self.recorder.recorder_factory)

        with mock.patch.object(runner.subprocess, "check_output", side_effect=["a" * 40 + "\n", ""]), \
                mock.patch.object(runner.subprocess, "run", side_effect=run), \
                mock.patch.object(runner.subprocess, "Popen", side_effect=popen), \
                mock.patch.object(Session, "capture", capture):
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                status = runner.main([
                    "--run-directory", str(self.root), "--derived-data", str(derived_data),
                    "--target-udid", "synthetic-target", "--variant", "generated", "--scenario", "scroll",
                    "--iteration", "2", "--source-revision", "a" * 40,
                    "--readiness-timeout", "0.5", "--completion-timeout", "0.5",
                ])
        _, process_stderr = self.recorder.process.communicate(timeout=5)
        self.assertEqual(status, 0, process_stderr)
        self.assertEqual(json.loads(stdout.getvalue())["status"], "complete")
        self.assertEqual(original.read_bytes(), original_bytes)
        self.assertEqual(configured, {
            "PRODUCT_MODULE_NAME": "RefractBenchUITests", "XCODE_SCHEME_NAME": "RefractBench",
            "DYLD_LIBRARY_PATH": "__TESTROOT__/Release-iphonesimulator",
            "REFRACT_BENCH_REVISION": "a" * 40,
            "REFRACT_BENCH_TRACE_CONTROL": str(self.root / "control"),
            "REFRACT_BENCH_TRACE_ITERATION": "2",
        })
        self.assertEqual(self.recorder.process.returncode, 0)
        self.assertTrue(all((self.root / name).is_file() for name in TARGET_PROBE_FILENAMES))
        self.assertEqual(json.loads((self.root / "iteration-trace-config.json").read_text())["iteration"], 2)
        self.assertTrue((self.root / "refract-build-provenance.json").is_file())

    def test_reused_run_directory_or_trace_is_never_replaced(self):
        self.run_success()
        self.recorder.stop()
        original = (self.root / "raw/generated-scroll-2.trace.zip").read_bytes()
        # No preflight here: the previous run left packets behind, and capture
        # must fail closed rather than treat them as a fresh epoch.
        self.recorder.start()
        with self.assertRaisesRegex(HandshakeError, "new run directory|Refusing"):
            self.capture(self.session())
        self.assertEqual((self.root / "raw/generated-scroll-2.trace.zip").read_bytes(), original)

    def test_executed_or_archived_configuration_drift_is_rejected_before_capture(self):
        for target in ("executed", "archived"):
            with self.subTest(target=target):
                root = self.root / f"drift-{target}"
                recorder = RecorderFixture(root)
                session = self.session(run_directory=root, xcodebuild_log=recorder.output,
                                       control_directory=root / "control")
                self.launch(session=session, fixture=recorder)
                self.addCleanup(recorder.stop)
                path = (session.derived_data / "Build/Products/iteration-trace-config-0123456789abcdef01234567.xctestrun"
                        if target == "executed" else root / "iteration-trace-config.xctestrun")
                path.write_bytes(b"changed after preparation")
                with self.assertRaisesRegex(HandshakeError, "configuration|bytes|iteration"):
                    self.capture(session, recorder)
                self.assertFalse((root / "raw/iteration-trace.json").exists())
                self.assertIsNone(recorder.recorder)

    def test_final_configuration_drift_cannot_leave_a_complete_receipt(self):
        session = self.launch()
        original = validate_trace_configuration
        def drift_after_native_capture(*args, **kwargs):
            receipt = original(*args, **kwargs)
            (session.run_directory / "iteration-trace-config.xctestrun").write_bytes(b"changed during capture")
            return receipt
        with mock.patch("iteration_trace_runner.validate_trace_configuration", side_effect=drift_after_native_capture):
            with self.assertRaisesRegex(HandshakeError, "configuration|iteration"):
                self.capture(session)
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())

    def test_missing_stale_and_ambiguous_pid_fail_closed(self):
        for pid in (None, 0):
            with self.subTest(pid=pid):
                root = self.root / f"pid-{pid}"
                recorder = RecorderFixture(root)
                self.addCleanup(recorder.stop)
                session = self.launch(fixture=recorder,
                                      session_kwargs={"run_directory": root, "xcodebuild_log": recorder.output,
                                                      "control_directory": root / "control"}, pid=pid)
                with self.assertRaisesRegex(HandshakeError, "PID|pid|process"):
                    self.capture(session, recorder)
                self.assertFalse((root / "raw/generated-scroll-2.trace.zip").exists())
        root = self.root / "ambiguous-pid"
        recorder = RecorderFixture(root)
        self.addCleanup(recorder.stop)
        session = self.launch(fixture=recorder,
                              session_kwargs={"run_directory": root, "xcodebuild_log": recorder.output,
                                              "control_directory": root / "control"},
                              duplicate_request=True)
        with self.assertRaisesRegex(HandshakeError, "Ambiguous.*request"):
            self.capture(session, recorder)

    def test_later_iteration_has_one_completion_and_original_identity(self):
        session = self.launch(session_kwargs={"iteration": 29}, app_iteration=29)
        result = self.capture(session)
        self.assertEqual(result["iteration"], 29)
        self.assertEqual(result["native_iteration_completion"], "generated scroll complete 1")
        self.assertEqual(json.loads((self.root / "raw/completion.json").read_text())["iteration"], 29)
        self.assertTrue((self.root / "raw/generated-scroll-29.trace.zip").is_file())

    def test_iteration_30_preserves_all_completion_and_frame_identity(self):
        for scenario in ("scroll", "stateUpdate"):
            with self.subTest(scenario=scenario):
                root = self.root / f"iteration-30-{scenario}"
                recorder = RecorderFixture(root)
                self.addCleanup(recorder.stop)
                session = self.launch(
                    fixture=recorder,
                    session_kwargs={"run_directory": root, "xcodebuild_log": recorder.output,
                                    "control_directory": root / "control", "scenario": scenario,
                                    "iteration": 30},
                    app_iteration=30,
                    app_scenario=scenario,
                    completion=f"generated {scenario} complete 1",
                    final_samples=synthetic_final_samples(
                        scenario=scenario, iteration=30, recordedIteration=30,
                        iterationByFrame=[30, 30, 30]))
                result = self.capture(session, recorder)
                recorder.process.wait(timeout=5)
                self.assertEqual(result["iteration"], 30)
                self.assertEqual(result["scenario"], scenario)
                self.assertEqual(result["native_iteration_completion"], f"generated {scenario} complete 1")
                for name in ("request", "begin", "native-completion", "completion"):
                    packet = json.loads((root / f"control/{name}.json").read_text())
                    self.assertEqual(packet["iteration"], 30, name)
                    self.assertEqual(packet["variant"], "generated", name)
                    self.assertEqual(packet["scenario"], scenario, name)
                    self.assertEqual(packet["session"], 1, name)
                expected = synthetic_final_samples(scenario=scenario, iteration=30,
                                                   recordedIteration=30, iterationByFrame=[30, 30, 30])
                self.assertEqual(json.loads((root / "raw/native-samples.json").read_text()), expected)
                self.assertEqual(json.loads((root / "control/completion.json").read_text())["finalSamples"],
                                 expected)
                self.assertTrue((root / f"raw/generated-{scenario}-30.trace.zip").is_file())

    def test_stale_iteration_29_is_rejected_for_iteration_30_before_recorder_start(self):
        session = self.launch(session_kwargs={"iteration": 30}, app_iteration=29)
        with self.assertRaisesRegex(HandshakeError, "iteration.*expected 30.*got 29"):
            self.capture(session)
        self.assertIsNone(self.recorder.recorder)
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())

    def test_stale_session_is_rejected_before_recorder_start(self):
        # A stale session_id is rejected when the first identity packet arrives
        # from the synthetic test; the fresh control epoch is still valid.
        session = self.launch(session_kwargs={"session_id": 2})
        with self.assertRaisesRegex(HandshakeError, "session|stale"):
            self.capture(session)

    def test_stale_revision_is_rejected_before_recorder_start(self):
        root = self.root / "stale-revision"
        recorder = RecorderFixture(root)
        self.addCleanup(recorder.stop)
        session = self.launch(fixture=recorder,
                              session_kwargs={"run_directory": root, "xcodebuild_log": recorder.output,
                                              "control_directory": root / "control"},
                              app_revision="b" * 40)
        with self.assertRaisesRegex(HandshakeError, "revision|stale"):
            self.capture(session, recorder)
        self.assertIsNone(recorder.recorder)

    def test_wrong_identity_and_unexpected_completion_fail_closed(self):
        for field, value, completion in (
            ("variant", "reference", "reference scroll complete 1"),
            ("scenario", "stateUpdate", "generated stateUpdate complete 1"),
            ("iteration", 30, "generated scroll complete 1"),
        ):
            with self.subTest(field=field):
                root = self.root / f"identity-{field}"
                root.mkdir()
                recorder = RecorderFixture(root)
                self.addCleanup(recorder.stop)
                values = {field: value}
                session = self.launch(fixture=recorder,
                                      session_kwargs={"run_directory": root, "xcodebuild_log": recorder.output,
                                                      "control_directory": root / "control", **values},
                                      completion=completion)
                with self.assertRaisesRegex(HandshakeError, "identity|iteration|completion|variant|scenario"):
                    self.capture(session, recorder)
                self.assertFalse((root / "raw/generated-scroll-2.trace.zip").exists())

    def test_ambiguous_completion_is_not_selected(self):
        session = self.launch(duplicate_completion=True)
        with self.assertRaisesRegex(HandshakeError, "Ambiguous.*completion"):
            self.capture(session)
        self.assertFalse((self.root / "raw/generated-scroll-2.trace.zip").exists())

    def test_recorder_exit_before_ready_cannot_be_hidden(self):
        session = self.launch(ready=None, ready_delay=0.02)
        with self.assertRaisesRegex(HandshakeError, "recorder.*exit|exited"):
            self.capture(session)

    def test_recorder_without_readiness_marker_is_rejected(self):
        session = self.launch(ready="xctrace: recording started, output will be somewhere")
        with self.assertRaisesRegex(HandshakeError, "readiness|Starting recording"):
            self.capture(session)
        self.assertFalse((self.root / "control/recorder-ready.json").exists())

    def test_current_test_packets_may_arrive_during_provenance_checks(self):
        # The synthetic XCTest writes its identity packet immediately on launch
        # and then waits for recorder-ready. A slow build-provenance validation
        # forces the race: by the time provenance completes, the current test's
        # request.json (and possibly begin/completion) already exist. With the
        # frozen epoch, capture must reach the completion-payload assertion
        # rather than reclassify the current-run packets as pre-existing state.
        session = self.launch(completion="generated scroll complete 0")
        original = runner.validate_build_provenance
        validated = threading.Event()

        def slow_provenance(*args):
            original(*args)
            validated.set()
            time.sleep(0.15)

        with mock.patch("iteration_trace_runner.validate_build_provenance", side_effect=slow_provenance):
            with self.assertRaisesRegex(HandshakeError, "completion|PID"):
                self.capture(session)
        self.assertTrue(validated.is_set())
        self.assertTrue((self.root / "raw/request.json").is_file())
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())

    def test_stale_or_premature_packets_are_rejected_before_provenance(self):
        # No fresh control epoch is recorded: pre-existing packets before the
        # synthetic XCTest is launched must still fail closed.
        self.recorder.prepare()
        self.recorder.output.write_text("current synthetic test\n")
        self.recorder.process.terminate()
        self.recorder.process.wait(timeout=5)
        for name, packet in (
            ("begin.json", {}), ("native-completion.json", {}), ("completion.json", {}),
            ("unexpected.json", {}),
        ):
            with self.subTest(name=name):
                (self.root / "control" / name).write_text(json.dumps(packet))
                with self.assertRaisesRegex(HandshakeError, "stale control directory"):
                    self.capture(self.session())
                (self.root / "control" / name).unlink()
        for name, packet in (
            ("request.json", {"schema": 1, "session": 1, "revision": "a" * 40,
                              "variant": "generated", "scenario": "scroll", "iteration": 0,
                              "pid": 4242, "process": "running", "state": "ready"}),
            ("native-process.json", {"schema": 1, "session": 1, "revision": "a" * 40,
                                     "variant": "generated", "scenario": "scroll", "iteration": 0,
                                     "pid": 4242, "process": "running", "state": "ready"}),
        ):
            with self.subTest(name=name, change="wrong identity"):
                (self.root / "control" / name).write_text(json.dumps(dict(packet, revision="b" * 40)))
                with self.assertRaisesRegex(HandshakeError, "revision|stale"):
                    self.capture(self.session())
                (self.root / "control" / name).unlink()

    def test_pre_existing_completion_before_launch_is_rejected(self):
        # Explicit regression: a stale completion published before preflight
        # must be rejected by record_capture_start_epoch itself.
        stale = {"schema": 1, "session": 1, "revision": "a" * 40, "variant": "generated",
                 "scenario": "scroll", "iteration": 0, "pid": 4242, "process": "running",
                 "state": "complete", "completion": "generated scroll complete 1"}
        (self.root / "control" / "completion.json").write_text(json.dumps(stale))
        session = self.session()
        with self.assertRaisesRegex(HandshakeError, "stale control directory"):
            session.record_capture_start_epoch()

    def test_current_test_publishes_begin_and_completion_before_capture(self):
        # Deterministic regression for #374: a fast current test publishes a
        # valid Begin, native completion and forwarded completion before
        # Session.capture is invoked. The packets are written by the
        # replacement fake XCTest process itself, never by the fixture.
        # A deterministic two-phase gate drives the ordering: the fake
        # publishes request.json on launch, waits for the launch gate, then
        # writes Begin, native completion and forwarded completion and
        # signals the published gate. Only after that gate is durable does
        # the test call Session.capture, so every current-run packet is
        # already in place and capture must admit it through the normal
        # identity-checked request/readiness/Begin/native-completion
        # sequence rather than reject it as a reused control directory.
        control = self.root / "control"
        session = self.session()
        session.record_capture_start_epoch()

        packet = {"schema": 1, "session": 1, "revision": "a" * 40,
                  "variant": "generated", "scenario": "scroll", "iteration": 2,
                  "pid": 4242, "process": "running", "state": "ready"}
        complete = dict(packet, state="complete", completion="generated scroll complete 1")
        complete["finalSamples"] = synthetic_final_samples(frameIntervalMs=[16.5], iterationByFrame=[2])
        begin = dict(packet, state="begin")
        launch_gate = self.recorder.work / "launch-gate"
        published_gate = self.recorder.work / "published-gate"
        script = self.recorder.work / "fast_xcodebuild.py"
        script.write_text(f"""import json, pathlib, sys, time
control = pathlib.Path(sys.argv[1])
def publish(name, value):
    temporary = control / ('.' + name + '.tmp')
    temporary.write_text(json.dumps(value))
    temporary.rename(control / name)
launch_gate = pathlib.Path({str(launch_gate)!r})
published_gate = pathlib.Path({str(published_gate)!r})
# The fake XCTest itself publishes request.json on launch, then blocks on a
# deterministic gate. The fixture never writes any control packet.
(control / 'request.json').write_text(json.dumps({packet!r}))
while not launch_gate.exists():
    time.sleep(0.005)
# The gate is open: publish Begin, native completion and forwarded
# completion in this same process, then signal that they are durable.
publish('begin.json', {begin!r})
publish('native-completion.json', {complete!r})
publish('completion.json', {complete!r})
published_gate.write_text('published')
while not (control / 'recorder-finished.json').exists():
    time.sleep(0.01)
""")
        # Do not call RecorderFixture.prepare(): it would spawn the default
        # fake XCTest and write its request.json. Install only a recorder
        # factory and the synthetic xcodebuild log so capture can run.
        self.recorder.recorder_factory = self._make_recorder_factory()
        self.recorder.output.write_text("native XCTApplicationLaunchMetric remains unchanged\n",
                                        encoding="utf-8")
        self.recorder.process = subprocess.Popen(
            ["python3", "-I", str(script), str(control)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        def stop_fast_test():
            process = self.recorder.process
            if process.poll() is None:
                process.terminate()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=5)
        self.recorder.cleanup = stop_fast_test
        # Wait for request.json to be durable: the fake XCTest is running
        # and has crossed its launch boundary.
        deadline = time.monotonic() + 5
        while not (control / "request.json").exists() and time.monotonic() < deadline:
            time.sleep(0.005)
        self.assertTrue((control / "request.json").is_file(),
                        "fake XCTest did not publish its identity packet on launch")
        # Open the launch gate: the fake XCTest now writes Begin, native
        # completion and forwarded completion in its own process.
        launch_gate.write_text("launch")
        # Block until the published gate confirms every current-run packet
        # is durable. Only then is Session.capture invoked.
        deadline = time.monotonic() + 5
        while not published_gate.exists() and time.monotonic() < deadline:
            time.sleep(0.005)
        self.assertTrue(published_gate.is_file(),
                        "fake XCTest did not publish Begin/native-completion/completion before capture")
        for name in ("begin.json", "native-completion.json", "completion.json"):
            self.assertTrue((control / name).is_file(), f"missing {name} before capture")
        result = self.capture(session)
        self.assertEqual(result["status"], "complete")
        self.assertEqual(result["native_iteration_completion"], "generated scroll complete 1")
        self.assertTrue((self.root / "raw/iteration-trace.json").is_file())

    def _make_recorder_factory(self):
        # A minimal xctrace replacement that writes the trace package on
        # SIGINT, mirroring RecorderFixture.prepare's recorder without
        # launching any fake XCTest process.
        recorder_script = self.recorder.work / "fast_xcrun.py"
        recorder_script.write_text(f"""import json, os, pathlib, signal, sys
with open(os.environ["REFRACT_SYNTHETIC_XCRUN"], "a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\\n")
output = sys.argv[sys.argv.index("--output") + 1]
def finish(status):
    trace = pathlib.Path(output)
    (trace / "Data").mkdir(parents=True, exist_ok=True)
    (trace / "Data" / "samples.bin").write_bytes(b"synthetic package member")
    print("Output saved: " + output, flush=True)
    os._exit(status)
signal.signal(signal.SIGINT, lambda *_: finish(0))
signal.signal(signal.SIGTERM, lambda *_: finish(143))
print("Starting recording with the Animation Hitches template. Attach to stop.", flush=True)
while True:
    signal.pause()
""")

        def factory(command, log):
            environment = dict(os.environ, REFRACT_SYNTHETIC_XCRUN=str(self.recorder.commands))
            self.recorder.recorder = subprocess.Popen(
                ["python3", "-I", str(recorder_script), *command,
                 "--control-directory", str(self.root / "control")],
                env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            return self.recorder.recorder
        return factory

    def test_completion_injected_before_recorder_ready_is_rejected(self):
        session = self.launch(missing_begin=True)
        with self.assertRaisesRegex(HandshakeError, "begin|native-completion"):
            self.capture(session)
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())

    def test_wrong_completion_is_rejected_before_archiving(self):
        session = self.launch(completion="generated scroll complete 0")
        with self.assertRaisesRegex(HandshakeError, "completion|PID"):
            self.capture(session)
        self.assertTrue((self.root / "raw/request.json").is_file())
        self.assertTrue((self.root / "raw/recorder.log").is_file())
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())

    def test_missing_completion_preserves_diagnostics(self):
        session = self.launch(missing_completion=True)
        with self.assertRaisesRegex(HandshakeError, "timed out|Timed out"):
            self.capture(session)
        self.assertTrue((self.root / "raw/request.json").is_file())
        self.assertTrue((self.root / "raw/recorder.log").is_file())
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())

    def test_archiver_is_called_only_after_exact_completion(self):
        session = self.launch(write_trace=False)
        with self.assertRaisesRegex(HandshakeError, "did not save the exact requested trace package"):
            self.capture(session)
        self.assertFalse((self.root / "raw/generated-scroll-2.trace.zip").exists())
        self.assertTrue((self.root / "raw/completion.json").is_file())

    def test_saved_path_for_another_package_is_rejected(self):
        session = self.launch(saved_path="/tmp/another.trace")
        with self.assertRaisesRegex(HandshakeError, "exact requested trace"):
            self.capture(session)
        self.assertFalse((self.root / "control/recorder-finished.json").exists())

    def test_recorder_exit_before_completion_preserves_specific_failure(self):
        session = self.launch(recorder_after_ready_exit=7, completion_delay=0.2)
        with self.assertRaisesRegex(HandshakeError,
                                    "exited before native completion with status 7"):
            self.capture(session)
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())
        self.assertFalse((self.root / "raw/generated-scroll-2.trace.zip").exists())
        self.assertFalse((self.root / "control/recorder-finished.json").exists())

    def capture_stop_race(self, recorder):
        session = self.launch()
        self.recorder.recorder = recorder
        self.recorder.recorder_factory = lambda command, stream: recorder
        with self.assertRaisesRegex(HandshakeError, "exited with status 7"):
            self.capture(session)
        self.assertTrue((self.root / "raw/completion.json").is_file())
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())

    def test_recorder_exit_before_stop_is_not_overwritten_by_sigint(self):
        recorder = StopRaceRecorder(self.root / "control", 7)
        self.capture_stop_race(recorder)
        self.assertEqual(recorder.signals, [])
        self.assertEqual(recorder.returncode, 7)

    def test_recorder_sigint_lookup_failure_preserves_real_exit(self):
        recorder = StopRaceRecorder(self.root / "control", None,
                                    ProcessLookupError("recorder exited before SIGINT"))
        self.capture_stop_race(recorder)
        self.assertEqual(recorder.signals, [signal.SIGINT])
        self.assertEqual(recorder.returncode, 7)

    def test_recorder_failure_at_native_completion_never_accepts_trace(self):
        recorder = StopRaceRecorder(self.root / "control", 7)
        self.capture_stop_race(recorder)
        self.assertEqual(recorder.signals, [])
        self.assertEqual(recorder.returncode, 7)
        self.assertFalse((self.root / "raw/generated-scroll-2.trace.zip").exists())
        self.assertFalse((self.root / "control/recorder-finished.json").exists())

    def test_exact_existing_xctest_selectors_and_xctestrun_command(self):
        for variant in ("generated", "reference"):
            for scenario in ("scroll", "stateUpdate"):
                with self.subTest(variant=variant, scenario=scenario):
                    selector = f"test{variant.capitalize()}{scenario[0].upper()}{scenario[1:]}Trace"
                    test = traced_test_name(variant, scenario)
                    self.assertEqual(test.rsplit("/", 1)[-1], selector)
                    self.assertIn(f"func {selector}",
                                  (HERE / "RefractBenchUITests/RefractBenchUITests.swift").read_text())
        command = test_command(Path("iteration.xctestrun"), "owned-target",
                               "RefractBenchUITests/RefractBenchUITests/testGeneratedScrollTrace",
                               "a" * 40, Path("results.xcresult"))
        self.assertEqual(command[:3], ["xcodebuild", "test-without-building", "-xctestrun"])
        self.assertNotIn("-project", command)
        self.assertNotIn("simctl", command)

    def test_main_prepares_only_the_trace_xctestrun(self):
        source = (HERE / "iteration_trace_runner.py").read_text()
        prepare = source.index("test_run = prepare_test_run(")
        self.assertGreater(prepare, source.index('parser.add_argument("--variant"'))
        self.assertEqual(source[:prepare].count("\n        test_run = prepare_test_run("), 0)
        self.assertEqual(source[prepare:].count("prepare_test_run("), 1)
        self.assertLess(prepare, source.index('test_command(test_run', prepare))

    def test_real_xctrace_saved_output_spelling_is_accepted(self):
        self.assertEqual(SAVED_OUTPUT.findall(
            "Recording failed with errors. Saving output file...\n"
            "Output file saved as: generated-scroll-2.trace\n"), ["generated-scroll-2.trace"])
        self.assertEqual(SAVED_OUTPUT.findall("Output saved: generated-scroll-2.trace\n"),
                         ["generated-scroll-2.trace"])
        self.assertEqual(SAVED_OUTPUT.findall(
            "Output file saved as: generated-scroll-2.trace\n"
            "Output file saved as: generated-scroll-2.trace\n"),
            ["generated-scroll-2.trace", "generated-scroll-2.trace"])

        self.assertTrue(saved_trace_matches("generated-scroll-2.trace", self.trace))
        self.assertTrue(saved_trace_matches(str(self.trace), self.trace))
        self.assertFalse(saved_trace_matches("another.trace", self.trace))
        self.assertFalse(saved_trace_matches("subdir/generated-scroll-2.trace", self.trace))

    def test_actual_output_spelling_and_bare_package_are_archived(self):
        session = self.launch(saved_path=self.trace.name, saved_spelling="Output file saved as")
        result = self.capture(session)
        self.recorder.process.wait(timeout=5)
        self.assertEqual(result["status"], "complete")
        self.assertEqual(result["archived_package_name"], self.trace.name)
        self.assertTrue((self.root / result["trace"]).is_file())
        self.assertIn("Output file saved as: generated-scroll-2.trace\n",
                      (self.root / "raw/recorder.log").read_text())

    def test_actual_output_spelling_keeps_path_and_uniqueness_gates(self):
        cases = (
            {"saved_path": "/tmp/another.trace"},
            {"saved_path": f"another/{self.trace.name}"},
            {"write_trace": False},
            {"saved_lines": 2},
        )
        for index, arguments in enumerate(cases):
            with self.subTest(arguments=arguments):
                root = self.root / f"saved-output-gate-{index}"
                recorder = RecorderFixture(root)
                self.addCleanup(recorder.stop)
                session = self.launch(fixture=recorder,
                                      session_kwargs={"run_directory": root,
                                                      "xcodebuild_log": recorder.output,
                                                      "control_directory": root / "control"},
                                      saved_spelling="Output file saved as", **arguments)
                with self.assertRaisesRegex(HandshakeError, "exact requested trace"):
                    self.capture(session, recorder)
                self.assertFalse((root / "raw/iteration-trace.json").exists())
                self.assertFalse((root / "raw/generated-scroll-2.trace.zip").exists())

    def test_actual_output_spelling_never_accepts_failed_recorder(self):
        session = self.launch()
        recorder = StopRaceRecorder(
            self.root / "control", 7,
            stdout="Starting recording with the Animation Hitches template. Attach to stop.\n"
                   "Output file saved as: generated-scroll-2.trace\n")
        self.recorder.recorder = recorder
        self.recorder.recorder_factory = lambda command, stream: recorder
        with self.assertRaisesRegex(HandshakeError, "exited with status 7"):
            self.capture(session)
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())
        self.assertFalse((self.root / "raw/generated-scroll-2.trace.zip").exists())

    def test_swiftui_template_is_recorded_in_command_and_result_metadata(self):
        session = self.launch(session_kwargs={"template": "SwiftUI"},
                              ready="Starting recording with the SwiftUI template. Attach to stop.",
                              saved_path=self.trace.name, saved_spelling="Output file saved as")
        result = self.capture(session)
        self.recorder.process.wait(timeout=5)
        self.assertEqual(result["template"], "SwiftUI")
        receipt = json.loads((self.root / "raw/iteration-trace.json").read_text())
        self.assertEqual(receipt["template"], "SwiftUI")
        arguments = json.loads(self.recorder.commands.read_text().splitlines()[0])
        self.assertEqual(arguments[arguments.index("--template") + 1], "SwiftUI")
        self.assertEqual(arguments[arguments.index("--attach") + 1], "4242")
        self.assertEqual(arguments[arguments.index("--output") + 1], str(self.trace))
        self.assertEqual(receipt["recorder"], "xctrace")
        self.assertEqual(receipt["target_label"], "SIMULATOR")
        self.assertFalse(receipt["device_result"])

    def test_default_and_mismatched_templates_remain_explicit_and_fail_closed(self):
        result = self.run_success()
        self.assertEqual(result["template"], "Animation Hitches")
        arguments = json.loads(self.recorder.commands.read_text().splitlines()[0])
        self.assertEqual(arguments[arguments.index("--template") + 1], "Animation Hitches")
        self.recorder.stop()
        self.root = self.root / "mismatched-template"
        self.trace = self.root / "generated-scroll-2.trace"
        self.recorder = RecorderFixture(self.root)
        self.addCleanup(self.recorder.stop)
        session = self.launch(session_kwargs={"template": "SwiftUI"},
                              ready="Starting recording with the Time Profiler template. Attach to stop.")
        with self.assertRaisesRegex(HandshakeError, "different template: Time Profiler"):
            self.capture(session)
        self.assertFalse((self.root / "control/recorder-ready.json").exists())
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())

    def test_main_never_invokes_target_lifecycle(self):
        script = HERE / "iteration_trace_runner.py"
        result = subprocess.run([sys.executable, "-I", str(script), "--help"],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("already-running", result.stdout)
        self.assertNotIn("simctl boot", result.stdout)


class BoundedEvidenceReadTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.evidence = self.root / "evidence.json"

    def test_oversized_json_integer_is_a_controlled_handshake_error(self):
        self.evidence.write_text('{"frameIntervalMs": [' + "1" * 4301 + ']}')
        with self.assertRaisesRegex(HandshakeError, "Cannot read handshake evidence.json"):
            runner.read_json(self.evidence)

    def test_oversized_file_is_rejected_without_an_unbounded_read(self):
        limit = 4096
        payload = b"x" * (limit + 1)
        self.evidence.write_bytes(payload)
        with mock.patch.object(runner, "MAX_EVIDENCE_FILE_BYTES", limit), \
                mock.patch.object(Path, "read_bytes", side_effect=AssertionError("unbounded read")) as full_read, \
                self.assertRaisesRegex(HandshakeError, f"{limit}-byte bound"):
            runner.bounded_file_bytes(self.evidence)
        full_read.assert_not_called()
        self.assertEqual(self.evidence.read_bytes(), payload)

    def test_exact_limit_file_is_returned_complete(self):
        limit = 4096
        payload = bytes(range(256)) * (limit // 256)
        self.evidence.write_bytes(payload)
        with mock.patch.object(runner, "MAX_EVIDENCE_FILE_BYTES", limit), \
                mock.patch.object(Path, "read_bytes", side_effect=AssertionError("unbounded read")):
            self.assertEqual(runner.bounded_file_bytes(self.evidence), payload)

    def test_concurrent_growth_is_rejected_without_accepting_a_prefix(self):
        limit = 4096
        initial = b"x" * (limit // 2)
        appended = b"y" * (limit // 2 + 1)
        self.evidence.write_bytes(initial)
        original_bounded_regular_file = runner.bounded_regular_file
        growth_allowed = threading.Event()
        writer_finished = threading.Event()
        writer_errors = []

        def grow_file():
            try:
                if not growth_allowed.wait(timeout=5):
                    raise AssertionError("reader did not complete initial validation")
                with self.evidence.open("ab", buffering=0) as stream:
                    stream.write(appended)
                writer_finished.set()
            except BaseException as error:
                writer_errors.append(error)
                writer_finished.set()

        writer = threading.Thread(target=grow_file)
        writer.start()

        def grow_after_initial_validation(path):
            metadata = original_bounded_regular_file(path)
            if path == self.evidence:
                growth_allowed.set()
                writer.join(timeout=5)
                if not writer_finished.wait(timeout=5):
                    raise AssertionError("writer did not finish concurrent growth")
            return metadata

        try:
            with mock.patch.object(runner, "MAX_EVIDENCE_FILE_BYTES", limit), \
                    mock.patch.object(runner, "bounded_regular_file", side_effect=grow_after_initial_validation), \
                    mock.patch.object(Path, "read_bytes", side_effect=AssertionError("unbounded read")) as full_read, \
                    self.assertRaisesRegex(HandshakeError, f"{limit}-byte bound"):
                runner.bounded_file_bytes(self.evidence)
            full_read.assert_not_called()
        finally:
            growth_allowed.set()
            writer_finished.set()
            writer.join(timeout=5)
        self.assertFalse(writer.is_alive())
        self.assertEqual(writer_errors, [])
        self.assertEqual(self.evidence.read_bytes(), initial + appended)


class TraceBuildProvenanceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.derived_data = self.root / "DerivedData"
        products = self.derived_data / "Build/Products/Release-iphonesimulator"
        (products / "RefractBench.app").mkdir(parents=True)
        (products / "RefractBenchUITests-Runner.app/PlugIns/RefractBenchUITests.xctest").mkdir(parents=True)
        (products / "RefractBenchUITests-Runner.app/RefractBenchUITests-Runner").write_bytes(b"synthetic runner A")
        (products / "RefractBenchUITests-Runner.app/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "RefractBenchUITests-Runner",
        }))
        (products / "RefractBenchUITests-Runner.app/Frameworks").mkdir()
        (products / "RefractBenchUITests-Runner.app/Frameworks/Support.dylib").write_bytes(b"support library A")
        (products / "RefractBenchUITests-Runner.app/Base.lproj").mkdir()
        (products / "RefractBenchUITests-Runner.app/Base.lproj/Localizable.strings").write_bytes(b"resource A")
        (products / "RefractBenchUITests-Runner.app/_CodeSignature").mkdir()
        (products / "RefractBenchUITests-Runner.app/_CodeSignature/CodeResources").write_bytes(b"unsigned fixture")
        (products / "RefractBench.app/RefractBench").write_bytes(b"synthetic app A")
        (products / "RefractBench.app/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "RefractBench",
        }))
        test_bundle = products / "RefractBenchUITests-Runner.app/PlugIns/RefractBenchUITests.xctest"
        (test_bundle / "RefractBenchUITests").write_bytes(b"synthetic test A")
        (test_bundle / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "RefractBenchUITests",
        }))
        self.source = self.derived_data / "Build/Products/RefractBench.xctestrun"
        self.source.write_bytes(plistlib.dumps({
            "RefractBenchUITests": {"TestingEnvironmentVariables": {
                "DYLD_LIBRARY_PATH": "__TESTROOT__/Release-iphonesimulator",
                "DYLD_FRAMEWORK_PATH": "__TESTROOT__/Release-iphonesimulator",
                "XCODE_SCHEME_NAME": "RefractBench",
            }},
        }))
        record_build_provenance(self.derived_data, "a" * 40)

    def prepare(self, iteration):
        run = self.root / f"run-{iteration}"
        self.make_run(run)
        return self.prepare_run(run, iteration)

    def make_run(self, run):
        (run / "control").mkdir(parents=True)

    def prepare_run(self, run, iteration):
        def synthetic_plutil(command, check, capture_output=False, text=False):
            if command[1] == "-convert":
                destination = Path(command[command.index("-o") + 1])
                destination.write_bytes(plistlib.dumps(plistlib.loads(self.source.read_bytes()),
                                                       fmt=plistlib.FMT_BINARY))
            elif command[1] == "-extract":
                values = plistlib.loads(Path(command[-1]).read_bytes())
                values = values["RefractBenchUITests"]["TestingEnvironmentVariables"]
                return subprocess.CompletedProcess(command, 0, json.dumps(values), "")
            else:
                destination = Path(command[-1])
                value = plistlib.loads(destination.read_bytes())
                value["RefractBenchUITests"]["TestingEnvironmentVariables"][command[2].rsplit(".", 1)[-1]] = command[4]
                destination.write_bytes(plistlib.dumps(value, fmt=plistlib.FMT_BINARY))
        with mock.patch("iteration_trace_runner.subprocess.run", side_effect=synthetic_plutil):
            return prepare_test_run(self.derived_data, run / "control", "a" * 40, iteration, run,
                                    validate_build_provenance(self.derived_data, "a" * 40))

    def test_consecutive_preparations_retain_exact_configuration_identity(self):
        original = self.source.read_bytes()
        first = self.prepare(29)
        first_bytes = first.read_bytes()
        second = self.prepare(30)
        self.assertNotEqual(first, second)
        self.assertEqual(first.read_bytes(), first_bytes)
        self.assertEqual(self.source.read_bytes(), original)
        for path, iteration in ((first, 29), (second, 30)):
            with self.subTest(iteration=iteration):
                run = self.root / f"run-{iteration}"
                self.assertEqual(run, self.root / f"run-{iteration}")
                receipt = json.loads((run / "iteration-trace-config.json").read_text())
                self.assertEqual(path.parent, self.derived_data / "Build/Products")
                self.assertTrue(path.is_file())
                self.assertEqual((run / "iteration-trace-config.xctestrun").read_bytes(), path.read_bytes())
                self.assertEqual(original_test_run(self.derived_data,
                                                   validate_build_provenance(self.derived_data, "a" * 40)),
                                 self.source)
                self.assertEqual(receipt["path"], path.name)
                self.assertEqual(receipt["archive"], "iteration-trace-config.xctestrun")
                self.assertEqual(receipt["configuration_sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
                archived_manifest = run / "refract-build-provenance.json"
                self.assertEqual(receipt["build_provenance_sha256"], hashlib.sha256(archived_manifest.read_bytes()).hexdigest())
                self.assertEqual(json.loads(archived_manifest.read_text())["source_revision"], "a" * 40)
                self.assertEqual(receipt["source_revision"], "a" * 40)
                self.assertEqual(receipt["control_directory"], str(run / "control"))
                self.assertEqual(receipt["iteration"], iteration)
                values = plistlib.loads(path.read_bytes())["RefractBenchUITests"]["TestingEnvironmentVariables"]
                self.assertEqual({name: values[name] for name in (
                    "REFRACT_BENCH_REVISION", "REFRACT_BENCH_TRACE_CONTROL", "REFRACT_BENCH_TRACE_ITERATION"
                )}, {"REFRACT_BENCH_REVISION": "a" * 40,
                     "REFRACT_BENCH_TRACE_CONTROL": str(run / "control"),
                     "REFRACT_BENCH_TRACE_ITERATION": str(iteration)})
                self.assertEqual(values["XCODE_SCHEME_NAME"], "RefractBench")
                self.assertIn("DYLD_LIBRARY_PATH", values)
                (run / "control/iteration-marker").write_text(str(iteration))
        self.assertNotEqual(first.read_bytes(), second.read_bytes())
        with self.assertRaisesRegex(HandshakeError, "Refusing to replace|new run"):
            prepare_test_run(self.derived_data, self.root / "run-29/control", "a" * 40, 29,
                             self.root / "run-29", validate_build_provenance(self.derived_data, "a" * 40))
        self.assertEqual(first.read_bytes(), first_bytes)

    def test_only_the_thirty_existing_traced_identities_are_admitted(self):
        self.assertEqual(list(runner.TRACED_ITERATIONS), list(range(2, 31)))
        for iteration in (29, 30):
            with self.subTest(entry="session", iteration=iteration):
                run = self.root / f"boundary-session-{iteration}"
                self.make_run(run)
                log = run / "xcodebuild.log"
                log.write_text("synthetic test\n")
                session = Session(target="synthetic-target", variant="generated", scenario="scroll",
                                  iteration=iteration, revision="a" * 40, run_directory=run,
                                  xcodebuild_log=log, control_directory=run / "control",
                                  derived_data=self.derived_data)
                self.assertEqual(session.iteration, iteration)
            with self.subTest(entry="prepare", iteration=iteration):
                self.prepare(iteration)
        for iteration in (31, 1, 0, 30.0, True):
            with self.subTest(entry="session", iteration=iteration):
                run = self.root / f"rejected-session-{iteration}"
                self.make_run(run)
                log = run / "xcodebuild.log"
                log.write_text("synthetic test\n")
                with self.assertRaisesRegex(HandshakeError, r"Iteration must be in 2\.\.30"):
                    Session(target="synthetic-target", variant="generated", scenario="scroll",
                            iteration=iteration, revision="a" * 40, run_directory=run,
                            xcodebuild_log=log, control_directory=run / "control")
            with self.subTest(entry="prepare", iteration=iteration):
                run = self.root / f"rejected-prepare-{iteration}"
                self.make_run(run)
                with mock.patch("iteration_trace_runner.subprocess.run") as plutil:
                    with self.assertRaisesRegex(HandshakeError, r"iteration in 2\.\.30"):
                        self.prepare_run(run, iteration)
                plutil.assert_not_called()
                self.assertEqual(list((run / "control").iterdir()), [])

    def test_failed_preparation_keeps_publication_and_never_deletes_replacement(self):
        run = self.root / "failed-run"
        self.make_run(run)
        published = None
        converted = None
        other_bytes = b"another preparation replaced this published path"

        def publish_then_replace(command, check, capture_output=False, text=False):
            nonlocal published, converted
            if command[1] == "-convert":
                converted = Path(command[4])
                converted.write_bytes(self.source.read_bytes())
                published = self.derived_data / "Build/Products" / converted.name
                return subprocess.CompletedProcess(command, 0)
            published.write_bytes(other_bytes)
            raise OSError("synthetic failure after publication")

        for attempt in range(2):
            with self.subTest(retry=attempt):
                with mock.patch("iteration_trace_runner.subprocess.run", side_effect=publish_then_replace):
                    expected = OSError if attempt == 0 else HandshakeError
                    with self.assertRaises(expected) as raised:
                        prepare_test_run(self.derived_data, run / "control", "a" * 40, 2, run,
                                         validate_build_provenance(self.derived_data, "a" * 40))
                    if attempt == 0:
                        self.assertRegex(str(raised.exception), "synthetic failure after publication")
                    else:
                        self.assertRegex(str(raised.exception), "Refusing to replace")
                self.assertEqual(published.read_bytes(), other_bytes)
                self.assertFalse((run / "iteration-trace-config.xctestrun").exists())
                self.assertFalse((run / "iteration-trace-config.json").exists())

    def test_receipt_failure_retains_public_destination_and_rejects_retry(self):
        run = self.root / "receipt-failure-run"
        self.make_run(run)
        original_atomic_json = runner.atomic_json
        original_link = os.link
        published = None
        def retain_link(source, destination):
            nonlocal published
            original_link(source, destination)
            published = Path(destination)
        def fail_receipt(path, payload):
            if path == run / "iteration-trace-config.json":
                raise OSError("receipt write failed")
            original_atomic_json(path, payload)
        with mock.patch("iteration_trace_runner.atomic_json", side_effect=fail_receipt), \
                mock.patch("iteration_trace_runner.os.link", side_effect=retain_link):
            with self.assertRaisesRegex(OSError, "receipt write failed"):
                self.prepare_run(run, 2)
        self.assertIsNotNone(published)
        self.assertTrue(published.is_file())
        self.assertFalse((run / "iteration-trace-config.json").exists())
        (run / "iteration-trace-config.xctestrun").unlink()
        (run / "refract-build-provenance.json").unlink()
        with self.assertRaisesRegex(HandshakeError, "Refusing to replace"):
            self.prepare_run(run, 2)

    def test_failed_conversion_does_not_remove_another_preparations_destination(self):
        run = self.root / "concurrent-run"
        self.make_run(run)
        other_bytes = b"another preparation owns this destination"
        published = None

        def concurrent_convert(command, check):
            nonlocal published
            converted = Path(command[4])
            converted.write_bytes(self.source.read_bytes())
            published = self.derived_data / "Build/Products" / converted.name
            published.write_bytes(other_bytes)
            raise OSError("synthetic concurrent conversion failure")

        with mock.patch("iteration_trace_runner.subprocess.run", side_effect=concurrent_convert):
            with self.assertRaisesRegex(OSError, "concurrent conversion failure"):
                prepare_test_run(self.derived_data, run / "control", "a" * 40, 2, run,
                                 validate_build_provenance(self.derived_data, "a" * 40))
        identity = hashlib.sha256(f"{'a' * 40}\0{run / 'control'}\00".encode()).hexdigest()[:24]
        destination = self.derived_data / "Build/Products" / f"iteration-trace-config-{identity}.xctestrun"
        self.assertEqual(published.read_bytes(), other_bytes)
        self.assertFalse((run / "iteration-trace-config.json").exists())

    def test_product_replacement_after_prepare_is_rejected_before_capture(self):
        run = self.root / "capture-products-run"
        self.make_run(run)
        self.prepare_run(run, 2)
        (run / "control").rmdir()
        (run / "control").mkdir()
        executable = (self.derived_data / "Build/Products/Release-iphonesimulator/"
                      "RefractBench.app/RefractBench")
        executable.write_bytes(b"products replaced before capture")
        (run / "xcodebuild.log").write_text("synthetic test log\n")
        with mock.patch("iteration_trace_runner.subprocess.run") as plutil:
            with self.assertRaisesRegex(HandshakeError, "product|digest|identity"):
                session = Session(target="synthetic-target", variant="generated", scenario="scroll", iteration=2,
                                  revision="a" * 40, run_directory=run,
                                  xcodebuild_log=run / "xcodebuild.log",
                                  control_directory=run / "control", derived_data=self.derived_data)
                # No XCTest is launched in this fixture; recording the epoch on
                # an empty directory keeps the build-provenance failure on the
                # path under test.
                session.record_capture_start_epoch()
                session.capture(mock.Mock())
        plutil.assert_not_called()

    def test_product_replacement_after_prepare_is_rejected_before_xctest_launch(self):
        target = self.root / "target.json"
        target.write_text(json.dumps({"target_label": "SIMULATOR", "device_result": False,
                                      "udid": "synthetic-target"}))

        def source_at_a(command, text):
            return "a" * 40 + "\n" if command[-1] == "HEAD" else ""

        def prepare_and_replace(*args):
            path = self.prepare_run(args[4], args[3])
            executable = (self.derived_data / "Build/Products/Release-iphonesimulator/"
                          "RefractBench.app/RefractBench")
            executable.write_bytes(b"products replaced after provenance validation")
            return path

        with mock.patch("iteration_trace_runner.subprocess.check_output", side_effect=source_at_a), \
             mock.patch("iteration_trace_runner.prepare_test_run", side_effect=prepare_and_replace), \
             mock.patch("iteration_trace_runner.validate_trace_configuration"), \
             mock.patch("iteration_trace_runner.test_command") as launch, \
             mock.patch("iteration_trace_runner.subprocess.Popen") as process:
            status = main(["--run-directory", str(self.root / "replaced-before-launch"),
                           "--derived-data", str(self.derived_data),
                           "--target-udid", "synthetic-target", "--target-metadata", str(target),
                           "--variant", "generated", "--scenario", "scroll", "--iteration", "2",
                           "--source-revision", "a" * 40])
        self.assertEqual(status, 2)
        launch.assert_not_called()
        process.assert_not_called()

    def test_product_replacement_during_capture_is_rejected_before_trace_acceptance(self):
        run = self.root / "replacement-run"
        recorder = RecorderFixture(run, create_run_directory=False)
        self.addCleanup(recorder.stop)
        self.make_run(run)
        self.prepare_run(run, 2)
        session = Session(target="synthetic-target", variant="generated", scenario="scroll", iteration=2,
                          revision="a" * 40, run_directory=run, xcodebuild_log=recorder.output,
                          control_directory=run / "control", readiness_timeout=0.5, completion_timeout=0.5,
                          derived_data=self.derived_data)
        # Freeze the epoch before the synthetic XCTest publishes any packets.
        recorder.start(preflight=session.record_capture_start_epoch)
        original_validation = validate_trace_configuration

        def replace_products_after_final_configuration_check(*args, **kwargs):
            receipt = original_validation(*args, **kwargs)
            executable = (self.derived_data / "Build/Products/Release-iphonesimulator/"
                          "RefractBench.app/RefractBench")
            executable.write_bytes(b"products replaced while XCTest was running")
            return receipt

        def synthetic_environment(command, check, capture_output, text):
            values = plistlib.loads(Path(command[-1]).read_bytes())
            values = values["RefractBenchUITests"]["TestingEnvironmentVariables"]
            return subprocess.CompletedProcess(command, 0, json.dumps(values), "")

        with mock.patch("iteration_trace_runner.validate_trace_configuration",
                        side_effect=replace_products_after_final_configuration_check), \
                mock.patch("iteration_trace_runner.subprocess.run", side_effect=synthetic_environment), \
                self.assertRaisesRegex(HandshakeError, "product|digest|identity"):
            session.capture(recorder.process, recorder.recorder_factory)
        self.assertFalse((run / "raw/iteration-trace.json").exists())

    def test_ambiguous_original_xctestrun_is_rejected_after_provenance_validation(self):
        self.source.with_name("second.xctestrun").write_bytes(b"second")
        run = self.root / "ambiguous-run"
        self.make_run(run)
        with mock.patch("iteration_trace_runner.subprocess.run") as plutil:
            with self.assertRaisesRegex(HandshakeError, "Exactly one.*generated xctestrun"):
                self.prepare_run(run, 2)
        plutil.assert_not_called()

    def test_build_products_from_a_are_rejected_at_b_head_before_launch(self):
        manifest = validate_build_provenance(self.derived_data, "a" * 40)
        first_digest = manifest["products"]["RefractBench.app"]["files"][0]["sha256"]
        self.assertEqual(manifest, validate_build_provenance(self.derived_data, "a" * 40))
        with self.assertRaisesRegex(HandshakeError, "source revision"):
            validate_build_provenance(self.derived_data, "b" * 40)
        executable = self.derived_data / "Build/Products/Release-iphonesimulator/RefractBench.app/RefractBench"
        executable.write_bytes(b"synthetic app rebuilt from B")
        with self.assertRaisesRegex(HandshakeError, "digest|changed|identity"):
            validate_build_provenance(self.derived_data, "a" * 40)
        self.assertEqual(json.loads(manifest["path"].read_text())["products"]["RefractBench.app"]["files"][0]["sha256"],
                         first_digest)
        manifest["path"].unlink()
        with self.assertRaisesRegex(HandshakeError, "provenance|manifest"):
            validate_build_provenance(self.derived_data, "a" * 40)

    def test_fifo_original_xctestrun_is_rejected_without_reading_it(self):
        self.source.unlink()
        os.mkfifo(self.source)
        with self.assertRaisesRegex(HandshakeError, "xctestrun|ordinary"):
            validate_build_provenance(self.derived_data, "a" * 40)

    def test_runner_executable_and_info_plist_from_b_are_rejected(self):
        runner = self.derived_data / "Build/Products/Release-iphonesimulator/RefractBenchUITests-Runner.app"
        for relative, replacement in (("RefractBenchUITests-Runner", b"runner built from B"),
                                      ("Info.plist", b"test host metadata from B")):
            with self.subTest(file=relative):
                path = runner / relative
                original = path.read_bytes()
                path.write_bytes(replacement)
                with self.assertRaisesRegex(HandshakeError, "digest|identity|Info.plist"):
                    validate_build_provenance(self.derived_data, "a" * 40)
                path.write_bytes(original)
                self.assertTrue(validate_build_provenance(self.derived_data, "a" * 40))

    def test_original_xctestrun_and_test_bundle_cannot_change_after_recording(self):
        original = self.source.read_bytes()
        self.source.write_bytes(original + b"tampered")
        with self.assertRaisesRegex(HandshakeError, "xctestrun"):
            validate_build_provenance(self.derived_data, "a" * 40)
        self.source.write_bytes(original)
        test_executable = (self.derived_data / "Build/Products/Release-iphonesimulator/"
                           "RefractBenchUITests-Runner.app/PlugIns/RefractBenchUITests.xctest/RefractBenchUITests")
        test_executable.chmod(0o755)
        with self.assertRaisesRegex(HandshakeError, "digest|identity"):
            validate_build_provenance(self.derived_data, "a" * 40)
        test_executable.chmod(0o644)
        self.assertTrue(validate_build_provenance(self.derived_data, "a" * 40))
        empty = test_executable.parent / "empty-framework"
        empty.mkdir()
        with self.assertRaisesRegex(HandshakeError, "digest|identity"):
            validate_build_provenance(self.derived_data, "a" * 40)
        empty.rmdir()
        self.assertTrue(validate_build_provenance(self.derived_data, "a" * 40))
        link = test_executable.parent / "linked-executable"
        link.symlink_to(test_executable)
        with self.assertRaisesRegex(HandshakeError, "link|special"):
            validate_build_provenance(self.derived_data, "a" * 40)
        link.unlink()
        test_executable.write_bytes(b"test products from B")
        with self.assertRaisesRegex(HandshakeError, "digest|identity"):
            validate_build_provenance(self.derived_data, "a" * 40)

    def prepare_reporter_provenance(self, fixture):
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        fixture.manifest["environment"]["build_configuration"]["target"] = "iphonesimulator"
        products = self.derived_data / "Build/Products/Release-iphonesimulator"
        for executable in ("RefractBench.app/RefractBench",
                           "RefractBenchUITests-Runner.app/RefractBenchUITests-Runner",
                           "RefractBenchUITests-Runner.app/PlugIns/RefractBenchUITests.xctest/RefractBenchUITests"):
            (products / executable).chmod(0o755)
        destination = fixture.root / "producer" / Path(fixture.build_path).name
        recorded = record_build_provenance(self.derived_data, "a" * 40, destination=destination)
        return destination, recorded

    def test_existing_recorded_provenance_feeds_the_complete_paired_reporter(self):
        fixture = PAIRED_REPORTER_FIXTURE[0](methodName="test_complete_paired_samples_pass_without_claiming_device_gate")
        destination, recorded = self.prepare_reporter_provenance(fixture)
        self.assertEqual(recorded["configuration"], "Release-iphonesimulator")
        self.assertEqual(recorded["source_xctestrun"]["path"], "RefractBench.xctestrun")
        fixture.replace_bytes(fixture.build_path, destination.read_bytes())
        report = make_report(fixture.manifest, fixture.root)
        self.assertEqual(report["status"], "pass")
        self.assertEqual(report["environment"]["source_revision"], recorded["source_revision"])
        self.assertEqual(report["environment"]["build_provenance"]["sha256"],
                         hashlib.sha256(destination.read_bytes()).hexdigest())
        self.assertEqual(fixture.manifest["environment"]["build_provenance"]["sha256"],
                         hashlib.sha256((fixture.root / fixture.build_path).read_bytes()).hexdigest())
        self.assertEqual(json.loads(destination.read_text(encoding="utf-8")),
                         json.loads((fixture.root / fixture.build_path).read_text(encoding="utf-8")))

    def test_recorded_provenance_still_rejects_an_executable_identity_change(self):
        fixture = PAIRED_REPORTER_FIXTURE[0](methodName="test_complete_paired_samples_pass_without_claiming_device_gate")
        destination, _ = self.prepare_reporter_provenance(fixture)
        payload = json.loads(destination.read_text(encoding="utf-8"))
        executable = next(entry for entry in payload["products"]["RefractBench.app"]["files"]
                          if entry["path"] == "RefractBench.app/RefractBench")
        executable["executable"] = False
        fixture.replace_json(fixture.build_path, payload)
        with self.assertRaisesRegex(EvidenceError, "main executable"):
            make_report(fixture.manifest, fixture.root)
        payload["products"]["RefractBench.app"]["files"] = [
            entry for entry in payload["products"]["RefractBench.app"]["files"]
            if not entry["path"].endswith("/RefractBench")
        ]
        fixture.replace_json(fixture.build_path, payload)
        with self.assertRaisesRegex(EvidenceError, "missing its main executable"):
            make_report(fixture.manifest, fixture.root)

    def test_recorded_bundle_records_reject_directory_changes_and_removed_files(self):
        fixture = PAIRED_REPORTER_FIXTURE[0](methodName="test_complete_paired_samples_pass_without_claiming_device_gate")
        destination, recorded = self.prepare_reporter_provenance(fixture)
        runner_name = "RefractBenchUITests-Runner.app"
        nested_test = "RefractBenchUITests-Runner.app/PlugIns/RefractBenchUITests.xctest"
        self.assertIn(runner_name + "/PlugIns", recorded["products"][runner_name]["directories"])
        for field, product, mutate, message in (
                ("directories", runner_name,
                 lambda values: values.insert(0, "RefractBenchReference.app"), "outside its declared"),
                ("files", runner_name,
                 lambda values: values.append({"path": "RefractBenchReference.app/injected", "bytes": 1,
                                               "executable": False, "sha256": "0" * 64}), "outside its declared"),
                ("files", nested_test,
                 lambda values: values.clear(), "complete"),
        ):
            payload = json.loads(destination.read_text(encoding="utf-8"))
            mutate(payload["products"][product][field])
            fixture.replace_json(fixture.build_path, payload)
            with self.subTest(field=field, product=product), self.assertRaisesRegex(EvidenceError, message):
                make_report(fixture.manifest, fixture.root)

    def test_a_build_at_b_head_rejects_main_before_any_trace_preparation(self):
        target = self.root / "target.json"
        target.write_text(json.dumps({"target_label": "SIMULATOR", "device_result": False,
                                      "udid": "synthetic-target"}))
        def source_at_b(command, text):
            return "b" * 40 + "\n" if command[-1] == "HEAD" else ""
        with mock.patch("iteration_trace_runner.subprocess.check_output", side_effect=source_at_b), \
             mock.patch("iteration_trace_runner.prepare_test_run") as prepare, \
             mock.patch("iteration_trace_runner.test_command") as launch:
            status = main(["--run-directory", str(self.root / "ab-run"),
                           "--derived-data", str(self.derived_data),
                           "--target-udid", "synthetic-target", "--target-metadata", str(target),
                           "--variant", "generated", "--scenario", "scroll", "--iteration", "2",
                           "--source-revision", "b" * 40])
        self.assertEqual(status, 2)
        prepare.assert_not_called()
        launch.assert_not_called()

    def test_main_rejects_drift_after_prepare_before_xctest_launch(self):
        target = self.root / "target.json"
        target.write_text(json.dumps({"target_label": "SIMULATOR", "device_result": False,
                                      "udid": "synthetic-target"}))
        def source_at_a(command, text):
            return "a" * 40 + "\n" if command[-1] == "HEAD" else ""
        def prepare_and_change(*args):
            path = self.prepare_run(args[4], args[3])
            path.write_bytes(b"configuration changed before launch")
            return path
        with mock.patch("iteration_trace_runner.subprocess.check_output", side_effect=source_at_a), \
             mock.patch("iteration_trace_runner.prepare_test_run", side_effect=prepare_and_change), \
             mock.patch("iteration_trace_runner.test_command") as launch, \
             mock.patch("iteration_trace_runner.subprocess.Popen") as process:
            status = main(["--run-directory", str(self.root / "drifted-run"),
                           "--derived-data", str(self.derived_data),
                           "--target-udid", "synthetic-target", "--target-metadata", str(target),
                           "--variant", "generated", "--scenario", "scroll", "--iteration", "2",
                           "--source-revision", "a" * 40])
        self.assertEqual(status, 2)
        launch.assert_not_called()
        process.assert_not_called()

    def test_provenance_validation_precedes_xctestrun_preparation(self):
        source = (HERE / "iteration_trace_runner.py").read_text()
        validation = source.index("validate_build_provenance(args.derived_data")
        preparation = source.index("prepare_test_run(", validation)
        launch = source.index("test_command(", preparation)
        self.assertLess(validation, preparation)
        self.assertLess(preparation, launch)


if __name__ == "__main__":
    unittest.main()
