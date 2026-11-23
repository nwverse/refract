#!/usr/bin/env python3
"""Synthetic startup completion tests; no target, Xcode or Instruments is invoked."""

from __future__ import annotations

import hashlib
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from iteration_trace_runner import (HandshakeError, Session, checked_first_display, record_build_provenance,
                                    traced_test_name, unique_packet)


class StartupTraceRunnerTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.control = Path(temporary.name)

    def startup_completion(self, **changes):
        packet = {
            "schema": 1, "session": 1, "revision": "a" * 40,
            "variant": "generated", "scenario": "startup", "iteration": 0,
            "pid": 4242, "process": "running", "state": "complete",
            "completion": "generated startup complete 1",
            "firstDisplay": {"clock": "CACurrentMediaTime", "timestamp": 12345.25},
        }
        packet.update(changes)
        return packet

    def test_exact_startup_selector_preserves_cold_start_metric(self):
        for variant in ("generated", "reference"):
            with self.subTest(variant=variant):
                expected = (f"RefractBenchUITests/RefractBenchUITests/"
                            f"test{variant.capitalize()}StartupTrace")
                self.assertEqual(traced_test_name(variant, "startup"), expected)
                self.assertIn(f"func {expected.rsplit('/', 1)[-1]}",
                              (HERE / "RefractBenchUITests/RefractBenchUITests.swift").read_text())
        cold_start = (HERE / "RefractBenchUITests/RefractBenchUITests.swift").read_text()
        self.assertIn("measure(metrics: [XCTApplicationLaunchMetric()]", cold_start)
        self.assertIn("options.iterationCount = 30", cold_start)

    def test_first_display_rejects_missing_invalid_or_fabricated_values(self):
        valid = {"clock": "CACurrentMediaTime", "timestamp": 12345.25}
        self.assertEqual(checked_first_display({"firstDisplay": valid}), valid)
        for value in (
            None, {}, {"clock": "wallClock", "timestamp": 12345.25},
            {"clock": "CACurrentMediaTime", "timestamp": True},
            {"clock": "CACurrentMediaTime", "timestamp": 0},
            {"clock": "CACurrentMediaTime", "timestamp": -1},
            {"clock": "CACurrentMediaTime", "timestamp": float("nan")},
            {"clock": "CACurrentMediaTime", "timestamp": float("inf")},
            {"clock": "CACurrentMediaTime", "timestamp": 12345.25, "elapsed": 1},
        ):
            with self.subTest(value=value):
                with self.assertRaisesRegex(HandshakeError, "first-display"):
                    checked_first_display({"firstDisplay": value})

    def test_missing_stale_duplicate_and_mismatched_completion_fail_closed(self):
        session = mock.Mock(session_id=1, variant="generated", scenario="startup", iteration=0)
        for field, value in (
            ("schema", 2), ("session", 2),
            ("variant", "reference"), ("scenario", "scroll"), ("iteration", 1),
        ):
            with self.subTest(field=field, value=value):
                (self.control / "completion.json").write_text(
                    json.dumps(self.startup_completion(**{field: value})))
                with self.assertRaisesRegex(HandshakeError, "identity"):
                    unique_packet(self.control, "completion", session)
                (self.control / "completion.json").unlink()
        with self.assertRaisesRegex(HandshakeError, "Missing completion"):
            unique_packet(self.control, "completion", session)
        (self.control / "completion.json").write_text(json.dumps(self.startup_completion()))
        (self.control / "completion-2.json").write_text(json.dumps(self.startup_completion()))
        with self.assertRaisesRegex(HandshakeError, "Ambiguous"):
            unique_packet(self.control, "completion", session)

    def test_first_display_completion_must_be_finite_and_positive(self):
        for packet in (
            self.startup_completion(firstDisplay=None),
            self.startup_completion(firstDisplay={"clock": "CACurrentMediaTime", "timestamp": 0}),
            self.startup_completion(firstDisplay={"clock": "CACurrentMediaTime", "timestamp": True}),
        ):
            with self.subTest(packet=packet):
                with self.assertRaisesRegex(HandshakeError, "first-display"):
                    checked_first_display(packet)


class SyntheticStartupSession:
    def __init__(self, test: unittest.TestCase, packet: dict | None, completion: bool = True):
        temporary = tempfile.TemporaryDirectory()
        test.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.run = self.root / "run"
        self.control = self.run / "control"
        self.control.mkdir(parents=True)
        self.derived_data = self.root / "DerivedData"
        self.log = self.run / "xcodebuild.log"
        self.log.write_text("synthetic native test\n")
        self.packet = packet
        self.completion = completion
        self.test = test
        self.prepare_provenance()
        self.session = Session(target="synthetic-target", variant="generated", scenario="startup", iteration=0,
                               revision="a" * 40, run_directory=self.run, xcodebuild_log=self.log,
                               control_directory=self.control, readiness_timeout=0.5,
                               completion_timeout=0.2, derived_data=self.derived_data)
        self.processes = []
        test.addCleanup(self.stop)

    def prepare_provenance(self):
        products = self.derived_data / "Build/Products/Release-iphonesimulator"
        test_bundle = products / "RefractBenchUITests-Runner.app/PlugIns/RefractBenchUITests.xctest"
        test_bundle.mkdir(parents=True)
        for bundle, executable in ((products / "RefractBench.app", "RefractBench"),
                                   (products / "RefractBenchUITests-Runner.app", "RefractBenchUITests-Runner"),
                                   (test_bundle, "RefractBenchUITests")):
            bundle.mkdir(exist_ok=True)
            (bundle / executable).write_bytes(b"synthetic native build product")
            (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": executable}))
        (self.derived_data / "Build/Products/RefractBench.xctestrun").write_bytes(b"original")
        record_build_provenance(self.derived_data, "a" * 40)
        values = {"REFRACT_BENCH_REVISION": "a" * 40,
                  "REFRACT_BENCH_TRACE_CONTROL": str(self.control),
                  "REFRACT_BENCH_TRACE_ITERATION": "0"}
        destination = self.derived_data / "Build/Products/iteration-trace-config-0123456789abcdef01234567.xctestrun"
        destination.write_bytes(plistlib.dumps({"RefractBenchUITests": {"TestingEnvironmentVariables": values}}))
        archived = self.run / "iteration-trace-config.xctestrun"
        archived.write_bytes(destination.read_bytes())
        manifest = self.run / "refract-build-provenance.json"
        manifest.write_bytes(b'{"synthetic": "provenance"}\n')
        (self.run / "iteration-trace-config.json").write_text(json.dumps({
            "schema": 1, "path": destination.name, "archive": archived.name,
            "configuration_sha256": hashlib.sha256(archived.read_bytes()).hexdigest(),
            "build_provenance_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
            "source_revision": "a" * 40, "control_directory": str(self.control), "iteration": 0,
        }))

    def read_environment(self, command, check, capture_output, text):
        values = plistlib.loads(Path(command[-1]).read_bytes())
        values = values["RefractBenchUITests"]["TestingEnvironmentVariables"]
        return subprocess.CompletedProcess(command, 0, json.dumps(values), "")

    def start_process(self, script, command=()):
        process = subprocess.Popen([sys.executable, "-I", str(script), *command], stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True)
        self.processes.append(process)
        return process

    def recorder(self, command, stream):
        script = self.root / "recorder.py"
        script.write_text("""import pathlib, signal, sys
output = pathlib.Path(sys.argv[sys.argv.index('--output') + 1])
def finish(*_):
    (output / 'Data').mkdir(parents=True, exist_ok=True)
    (output / 'Data' / 'samples.bin').write_bytes(b'synthetic package member')
    print('Output saved: ' + str(output), flush=True)
    raise SystemExit(0)
signal.signal(signal.SIGINT, finish)
print('Starting recording with the Animation Hitches template.', flush=True)
signal.pause()
""")
        return self.start_process(script, command)

    def capture(self):
        packet = json.dumps(self.packet)
        script = self.root / "native.py"
        script.write_text(f"""import json, pathlib
control = pathlib.Path({str(self.control)!r})
(control / 'request.json').write_text(json.dumps({{
    'schema': 1, 'session': 1, 'revision': {'a' * 40!r}, 'variant': 'generated', 'scenario': 'startup',
    'iteration': 0, 'pid': 4242, 'process': 'running', 'state': 'ready'}}))
while not (control / 'recorder-ready.json').exists():
    pass
if {self.completion!r}:
    (control / 'completion.json').write_text({packet!r})
while not (control / 'recorder-finished.json').exists():
    pass
""")
        native = self.start_process(script)
        with mock.patch("iteration_trace_runner.subprocess.run", side_effect=self.read_environment):
            result = self.session.capture(native, self.recorder)
        if result["status"] == "complete":
            native.wait(timeout=5)
        return result

    def stop(self):
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=5)


class StartupTraceSessionTest(unittest.TestCase):
    startup_completion = StartupTraceRunnerTest.startup_completion

    def test_startup_capture_retains_native_first_display(self):
        capture = SyntheticStartupSession(self, self.startup_completion())
        result = capture.capture()
        self.assertEqual(result["native_first_display"],
                         {"clock": "CACurrentMediaTime", "timestamp": 12345.25})
        receipt = json.loads((capture.run / "raw/iteration-trace.json").read_text())
        self.assertEqual(receipt["native_first_display"], result["native_first_display"])

    def test_startup_capture_rejects_missing_or_mismatched_completion(self):
        for packet, complete in (
            (None, False),
            (self.startup_completion(firstDisplay=None), True),
            (self.startup_completion(revision="b" * 40), True),
            (self.startup_completion(pid=4243), True),
            (self.startup_completion(process="not-running"), True),
            (self.startup_completion(state="ready"), True),
            (self.startup_completion(completion="generated startup complete 0"), True),
        ):
            with self.subTest(packet=packet, complete=complete):
                capture = SyntheticStartupSession(self, packet, complete)
                with self.assertRaisesRegex(HandshakeError, "identity|PID|process|complete|first-display|Timed out"):
                    capture.capture()
                self.assertFalse((capture.run / "raw/iteration-trace.json").exists())
                self.assertFalse((capture.run / "raw/generated-startup-0.trace.zip").exists())


if __name__ == "__main__":
    unittest.main()
