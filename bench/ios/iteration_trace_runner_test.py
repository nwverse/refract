#!/usr/bin/env python3
"""Synthetic lifecycle tests; no target, Xcode or Instruments is invoked."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from archive_trace import ArchiveError
from iteration_trace_runner import HandshakeError, Session, test_command, traced_test_name


class RecorderFixture:
    """Separate fake XCTest and xctrace processes with observable commands."""

    def __init__(self, root: Path):
        self.root = root
        self.work = root.parent / f"{root.name}-synthetic-tools"
        self.work.mkdir(exist_ok=True)
        self.commands = self.work / "commands.jsonl"
        self.process = None
        self.cleanup = lambda: None
        self.output = root / "xcodebuild.log"
        root.mkdir(exist_ok=True)
        (root / "control").mkdir()

    def start(self, ready: str | None = "Starting recording with the Animation Hitches template. Attach to stop.",
              completion: str = "generated scroll complete 1", pid: int | None = 4242,
              session: int = 1, duplicate_completion: bool = False, duplicate_request: bool = False,
              recorder_after_ready_exit: int = 0, ready_delay: float = 0,
              write_trace: bool = True, process_state: str = "running",
              missing_completion: bool = False, app_iteration: int = 0,
              saved_path: str | None = None, recorder_stop_status: int = 0,
              completion_delay: float = 0):
        app_script = self.work / "fake_xcodebuild.py"
        app_script.write_text(f'''import json, pathlib, sys, time
control = pathlib.Path(sys.argv[1])
packet = {{"schema": 1, "session": {session}, "variant": "generated", "scenario": "scroll", "iteration": {app_iteration},
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
if not {missing_completion!r}:
    (control / "completion.json").write_text(json.dumps(packet))
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
    print("Output saved: " + ({saved_path!r} or output), flush=True)
    sys.exit(status)
signal.signal(signal.SIGINT, lambda *_: finish(0))
signal.signal(signal.SIGTERM, lambda *_: finish(143))
time.sleep({ready_delay!r})
if {ready!r} is None:
    sys.exit(7)
print({ready!r}.format(trace=output), flush=True)
if {recorder_after_ready_exit!r}:
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
        self.output.write_text("native XCTApplicationLaunchMetric remains unchanged\n", encoding="utf-8")
        self.process = subprocess.Popen(
            ["python3", "-I", str(app_script), str(self.root / "control")],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        def factory(command, log):
            environment = dict(os.environ, REFRACT_SYNTHETIC_XCRUN=str(self.commands))
            return subprocess.Popen(
                ["python3", "-I", str(recorder_script), *command,
                 "--control-directory", str(self.root / "control")],
                env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.recorder_factory = factory

        def stop():
            if self.process is not None:
                if self.process.poll() is None:
                    self.process.terminate()
                try:
                    self.process.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.communicate(timeout=5)
        self.cleanup = stop

    def stop(self):
        self.cleanup()


class IterationTraceRunnerTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.recorder = RecorderFixture(self.root)
        self.addCleanup(lambda: self.recorder.stop())
        self.environment = dict(os.environ, TARGET_UDID="synthetic-target")
        self.trace = self.root / "generated-scroll-0.trace"

    def session(self, **kwargs):
        values = dict(target="synthetic-target", variant="generated", scenario="scroll", iteration=0,
                      revision="a" * 40, run_directory=self.root, xcodebuild_log=self.recorder.output,
                      control_directory=self.root / "control", readiness_timeout=0.5, completion_timeout=0.5)
        values.update(kwargs)
        return Session(**values)

    def capture(self, session, fixture=None):
        fixture = fixture or self.recorder
        return session.capture(fixture.process, fixture.recorder_factory)

    def run_success(self):
        self.recorder.start()
        session = self.session()
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
        self.assertEqual(result["trace"], "raw/generated-scroll-0.trace.zip")
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
        self.assertFalse((self.root / "raw/generated-scroll-0.trace").exists())
        self.assertTrue((self.root / "raw/recorder-ready.json").is_file())
        self.assertTrue((self.root / "raw/completion.json").is_file())
        self.assertTrue((self.root / "raw/recorder.log").is_file())
        self.assertTrue((self.root / "xcodebuild.log").is_file())
        self.assertTrue((self.root / "raw/recorder-finished.json").is_file())
        self.assertEqual(result["archived_package_name"], "generated-scroll-0.trace")

    def test_reused_run_directory_or_trace_is_never_replaced(self):
        self.run_success()
        self.recorder.stop()
        original = (self.root / "raw/generated-scroll-0.trace.zip").read_bytes()
        self.recorder.start()
        with self.assertRaisesRegex(HandshakeError, "new run directory|Refusing"):
            self.capture(self.session())
        self.assertEqual((self.root / "raw/generated-scroll-0.trace.zip").read_bytes(), original)

    def test_missing_stale_and_ambiguous_pid_fail_closed(self):
        for pid in (None, 0):
            with self.subTest(pid=pid):
                root = self.root / f"pid-{pid}"
                recorder = RecorderFixture(root)
                recorder.start(pid=pid)
                self.addCleanup(recorder.stop)
                with self.assertRaisesRegex(HandshakeError, "PID|pid|process"):
                    self.capture(self.session(run_directory=root, xcodebuild_log=recorder.output,
                                              control_directory=root / "control"), recorder)
                self.assertFalse((root / "raw/generated-scroll-0.trace.zip").exists())
        root = self.root / "ambiguous-pid"
        recorder = RecorderFixture(root)
        recorder.start(duplicate_request=True)
        self.addCleanup(recorder.stop)
        with self.assertRaisesRegex(HandshakeError, "Ambiguous.*request"):
            self.capture(self.session(run_directory=root, xcodebuild_log=recorder.output,
                                      control_directory=root / "control"), recorder)

    def test_later_iteration_has_one_completion_and_original_identity(self):
        self.recorder.start(app_iteration=29)
        session = self.session(iteration=29)
        result = self.capture(session)
        self.assertEqual(result["iteration"], 29)
        self.assertEqual(result["native_iteration_completion"], "generated scroll complete 1")
        self.assertEqual(json.loads((self.root / "raw/completion.json").read_text())["iteration"], 29)
        self.assertTrue((self.root / "raw/generated-scroll-29.trace.zip").is_file())

    def test_stale_session_is_rejected_before_recorder_start(self):
        self.recorder.start()
        with self.assertRaisesRegex(HandshakeError, "session|stale"):
            self.capture(self.session(session_id=2))

    def test_wrong_identity_and_unexpected_completion_fail_closed(self):
        for field, value, completion in (
            ("variant", "reference", "reference scroll complete 1"),
            ("scenario", "stateUpdate", "generated stateUpdate complete 1"),
            ("iteration", 1, "generated scroll complete 1"),
        ):
            with self.subTest(field=field):
                root = self.root / f"identity-{field}"
                root.mkdir()
                recorder = RecorderFixture(root)
                recorder.start(completion=completion)
                self.addCleanup(recorder.stop)
                values = {field: value}
                with self.assertRaisesRegex(HandshakeError, "identity|iteration|completion|variant|scenario"):
                    self.capture(self.session(run_directory=root, xcodebuild_log=recorder.output,
                                              control_directory=root / "control", **values), recorder)
                self.assertFalse((root / "raw/generated-scroll-0.trace.zip").exists())

    def test_ambiguous_completion_is_not_selected(self):
        self.recorder.start(duplicate_completion=True)
        with self.assertRaisesRegex(HandshakeError, "Ambiguous.*completion"):
            self.capture(self.session())
        self.assertFalse((self.root / "raw/generated-scroll-0.trace.zip").exists())

    def test_recorder_exit_before_ready_cannot_be_hidden(self):
        self.recorder.start(ready=None, ready_delay=0.02)
        with self.assertRaisesRegex(HandshakeError, "recorder.*exit|exited"):
            self.capture(self.session())

    def test_recorder_without_readiness_marker_is_rejected(self):
        self.recorder.start(ready="xctrace: recording started, output will be somewhere")
        with self.assertRaisesRegex(HandshakeError, "readiness|Starting recording"):
            self.capture(self.session())
        self.assertFalse((self.root / "control/recorder-ready.json").exists())

    def test_wrong_completion_is_rejected_before_archiving(self):
        self.recorder.start(completion="generated scroll complete 0")
        with self.assertRaisesRegex(HandshakeError, "completion|PID"):
            self.capture(self.session())
        self.assertTrue((self.root / "raw/request.json").is_file())
        self.assertTrue((self.root / "raw/recorder.log").is_file())
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())

    def test_missing_completion_preserves_diagnostics(self):
        self.recorder.start(missing_completion=True)
        with self.assertRaisesRegex(HandshakeError, "timed out|Timed out"):
            self.capture(self.session())
        self.assertTrue((self.root / "raw/request.json").is_file())
        self.assertTrue((self.root / "raw/recorder.log").is_file())
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())

    def test_archiver_is_called_only_after_exact_completion(self):
        self.recorder.start(write_trace=False)
        with self.assertRaises((HandshakeError, ArchiveError)) as raised:
            self.capture(self.session())
        self.assertIsInstance(raised.exception, ArchiveError)
        self.assertFalse((self.root / "raw/generated-scroll-0.trace.zip").exists())
        self.assertTrue((self.root / "raw/completion.json").is_file())

    def test_saved_path_for_another_package_is_rejected(self):
        self.recorder.start(saved_path="/tmp/another.trace")
        with self.assertRaisesRegex(HandshakeError, "exact requested trace"):
            self.capture(self.session())
        self.assertFalse((self.root / "control/recorder-finished.json").exists())

    def test_recorder_exit_before_completion_preserves_specific_failure(self):
        self.recorder.start(recorder_after_ready_exit=7, completion_delay=0.2)
        with self.assertRaisesRegex(HandshakeError,
                                    "exited before native completion with status 7"):
            self.capture(self.session())
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())
        self.assertFalse((self.root / "raw/generated-scroll-0.trace.zip").exists())
        self.assertFalse((self.root / "control/recorder-finished.json").exists())

    def test_recorder_failure_at_native_completion_never_accepts_trace(self):
        self.recorder.start(recorder_stop_status=7)
        with self.assertRaisesRegex(HandshakeError,
                                    "exited with status 7; trace is not accepted"):
            self.capture(self.session())
        self.assertTrue((self.root / "raw/completion.json").is_file())
        self.assertFalse((self.root / "raw/iteration-trace.json").exists())
        self.assertFalse((self.root / "raw/generated-scroll-0.trace.zip").exists())
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

    def test_main_never_invokes_target_lifecycle(self):
        script = HERE / "iteration_trace_runner.py"
        result = subprocess.run([sys.executable, "-I", str(script), "--help"],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("already-running", result.stdout)
        self.assertNotIn("simctl boot", result.stdout)


if __name__ == "__main__":
    unittest.main()
