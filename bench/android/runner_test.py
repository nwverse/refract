import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).parent


class RunnerOrchestrationTest(unittest.TestCase):
    """Exercise shell wiring with stand-ins, never Android or a measurement."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "source"
        self.bench = self.root / "bench/android"
        self.bench.mkdir(parents=True)
        self.additional_output = self.bench / "benchmark/build/outputs/connected_android_test_additional_output"
        self.additional_output.mkdir(parents=True)
        shutil.copy(HERE / "run-emulator.sh", self.bench / "run-emulator.sh")
        shutil.copy(HERE / "preserve_failed_evidence.py", self.bench / "preserve_failed_evidence.py")
        self.preservation_command = [
            "python3", "-I", str(self.bench / "preserve_failed_evidence.py"),
            "--input-directory", str(self.additional_output),
            "--output", str(Path(self.temporary.name) / "run"),
            "--environment", str(Path(self.temporary.name) / "run/environment.json"),
            "--instrumentation-status", str(Path(self.temporary.name) / "run/instrumentation-status.json"),
            "--instrumentation-log", str(Path(self.temporary.name) / "run/instrumentation.log"),
            "--instrumentation-exit-code", "1",
        ]
        (self.bench / "gradlew").write_text(
            "#!/usr/bin/env bash\n"
            "printf '%s\\n' \"$@\" > \"$RUNNER_CAPTURE_DIR/gradle-arguments.txt\"\n"
            "printf '%s\\n' 'INSTRUMENTATION_STATUS: shortMsg=Process crashed.'\n"
            "printf '%s\\n' 'java.lang.IllegalStateException: lastFrameNs=null'\n"
            "if [ \"${RUNNER_WRITE_OUTPUT:-}\" = 1 ]; then\n"
            "  printf '%s' \"$RUNNER_ANDROIDX_JSON\" > \"$RUNNER_SOURCE/bench/android/benchmark/build/outputs/connected_android_test_additional_output/benchmarkData.json\"\n"
            "  printf 'synthetic incomplete trace\\n' > \"$RUNNER_SOURCE/bench/android/benchmark/build/outputs/connected_android_test_additional_output/generatedStartup_iter000_123.perfetto-trace\"\n"
            "  printf 'not AndroidX evidence\\n' > \"$RUNNER_SOURCE/bench/android/benchmark/build/outputs/connected_android_test_additional_output/ignored.txt\"\n"
            "fi\n"
            "if [ \"${RUNNER_DIRTY:-}\" = 1 ]; then : > \"$RUNNER_SOURCE/dirty.txt\"; fi\n"
            "exit \"${RUNNER_INSTRUMENTATION_STATUS:-0}\"\n"
        )
        (self.bench / "gradlew").chmod(0o755)
        (self.bench / "generate-and-compile.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
        (self.bench / "generate-and-compile.sh").chmod(0o755)
        (self.bench / "probe_target.py").write_text(
            "import json,sys\n"
            "revision=sys.argv[sys.argv.index('--source-revision')+1]\n"
            "output=sys.argv[sys.argv.index('--output')+1]\n"
            "json.dump({'status':'ready','emulator':True,'source_revision':revision,"
            "'android_serial':'synthetic-target'},open(output,'w'))\n"
        )
        (self.bench / "collect_results.py").write_text(
            "import json,os,sys\n"
            "environment=sys.argv[sys.argv.index('--environment')+1]\n"
            "output=sys.argv[sys.argv.index('--output')+1]\n"
            "metadata=json.load(open(environment))\n"
            "json.dump(metadata,open(os.environ['RUNNER_CAPTURE_DIR']+'/collected-environment.json','w'))\n"
            "json.dump({},open(output+'/evidence-manifest.json','w'))\n"
            "open(output+'/json-files.txt','w').close()\n"
        )
        (self.bench / "report.py").write_text(
            "import json,os,sys\n"
            "assert '--require-macro' in sys.argv\n"
            "assert '--environment' not in sys.argv\n"
            "environment=json.load(open(os.environ['RUNNER_CAPTURE_DIR']+'/collected-environment.json'))\n"
            "json.dump(sys.argv,open(os.environ['RUNNER_CAPTURE_DIR']+'/report-arguments.json','w'))\n"
            "sys.exit(0 if environment['status']=='ready' else 2)\n"
        )
        adb = self.root / "platform-tools/adb"
        adb.parent.mkdir()
        adb.write_text("#!/usr/bin/env bash\nexit 0\n")
        adb.chmod(0o755)
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True)
        (self.root / ".git/info").mkdir()
        (self.root / ".git/info/exclude").write_text("build/\n")
        subprocess.run(["git", "-C", str(self.root), "add", "bench/android/run-emulator.sh",
                        "bench/android/gradlew", "bench/android/generate-and-compile.sh",
                        "bench/android/probe_target.py", "bench/android/preserve_failed_evidence.py",
                        "bench/android/collect_results.py",
                        "bench/android/report.py", "platform-tools/adb"], check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=Benchmark Fixture",
                        "-c", "user.email=me@example.com", "commit", "--quiet", "-m", "Synthetic runner fixture"],
                       check=True)
        self.revision = subprocess.check_output(["git", "-C", str(self.root), "rev-parse", "HEAD"], text=True).strip()
        self.capture = Path(self.temporary.name) / "capture"
        self.capture.mkdir()

    def run_runner(self, dirty=False, instrumentation_status=0, write_output=False):
        output = Path(self.temporary.name) / "run"
        androidx_json = json.dumps({
            "context": {"payload": {"refract.sourceRevision": self.revision}},
            "benchmarks": [{
                "className": "dev.refract.bench.test.SettingsMacrobenchmark",
                "name": "generatedStartup", "repeatIterations": 10,
                "metrics": {"startupMs": {"runs": [1, None, 3]}},
                "diagnosticStartup": [{"lastFrameNs": None}],
                "profilerOutputs": [{
                    "type": "PerfettoTrace", "label": "Trace Iteration 0",
                    "filename": "generatedStartup_iter000_123.perfetto-trace",
                }],
            }],
        })
        environment = dict(os.environ,
                           GIT_AUTHOR_NAME="Benchmark Fixture", GIT_AUTHOR_EMAIL="me@example.com",
                           GIT_COMMITTER_NAME="Benchmark Fixture", GIT_COMMITTER_EMAIL="me@example.com",
                           JAVA_HOME=os.environ.get("JAVA_HOME", "/usr"),
                           ANDROID_HOME=str(self.root),
                           RUNNER_CAPTURE_DIR=str(self.capture), RUNNER_SOURCE=str(self.root),
                           RUNNER_DIRTY="1" if dirty else "0",
                           RUNNER_INSTRUMENTATION_STATUS=str(instrumentation_status),
                           RUNNER_WRITE_OUTPUT="1" if write_output else "0",
                           RUNNER_ANDROIDX_JSON=androidx_json)
        return subprocess.run([str(self.bench / "run-emulator.sh"), str(output)],
                              env=environment, capture_output=True, text=True, check=False)

    def test_revision_reaches_gradle_and_verified_environment(self):
        result = self.run_runner()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = (self.capture / "gradle-arguments.txt").read_text()
        self.assertIn("-Pandroid.test.devices=synthetic-target", arguments)
        self.assertIn("-Pandroid.testInstrumentationRunnerArguments."
                      f"androidx.benchmark.output.payload.refract.sourceRevision={self.revision}", arguments)
        environment = json.loads((self.capture / "collected-environment.json").read_text())
        self.assertEqual(environment["source_revision"], self.revision)
        self.assertEqual(environment["status"], "ready")
        self.assertIn("worktree clean", environment["source_tree"])

    def test_dirty_source_blocks_collection(self):
        result = self.run_runner(dirty=True)
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.capture / "collected-environment.json").exists())
        self.assertFalse((self.capture / "report-arguments.json").exists())
        self.assertNotIn("Verified macro report", result.stdout)

    def test_instrumentation_failure_preserves_raw_diagnostics_without_pass(self):
        historical = self.additional_output / "historical"
        historical.mkdir()
        (historical / "historical_benchmarkData.json").write_text('{"historical": true}')
        (historical / "historical.perfetto-trace").write_text("not this run\n")
        result = self.run_runner(instrumentation_status=1, write_output=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        output = Path(self.temporary.name) / "run"
        self.assertFalse((self.capture / "collected-environment.json").exists())
        self.assertFalse((self.capture / "report-arguments.json").exists())
        self.assertFalse((output / "evidence-manifest.json").exists())
        self.assertFalse((output / "report.json").exists())
        self.assertFalse((output / "report.md").exists())
        self.assertNotIn("Verified macro report", result.stdout)
        self.assertIn("not passing evidence", result.stderr)

        preserved_json = output / "raw/additional-output/benchmarkData.json"
        payload = json.loads(preserved_json.read_text())
        self.assertIsNone(payload["benchmarks"][0]["diagnosticStartup"][0]["lastFrameNs"])
        self.assertIn(None, payload["benchmarks"][0]["metrics"]["startupMs"]["runs"])
        self.assertEqual((output / "raw/additional-output/generatedStartup_iter000_123.perfetto-trace").read_text(),
                         "synthetic incomplete trace\n")
        self.assertFalse((output / "raw/additional-output/ignored.txt").exists())
        self.assertFalse((output / "raw/additional-output/historical").exists())
        self.assertEqual((output / "pre-existing-additional-output/historical/"
                                  "historical_benchmarkData.json").read_text(), '{"historical": true}')
        self.assertIn("lastFrameNs=null", (output / "raw/instrumentation.log").read_text())

        manifest = json.loads((output / "failed-evidence-manifest.json").read_text())
        self.assertEqual(manifest["status"], "failed")
        self.assertIs(manifest["complete"], False)
        self.assertIs(manifest["diagnostic_only"], True)
        self.assertIs(manifest["device_result"], False)
        self.assertIs(manifest["instrumentation"]["deadline_exceeded"], False)
        for artifact in manifest["artifacts"]:
            retained = output / artifact["path"]
            self.assertEqual(retained.stat().st_size, artifact["bytes"])
            self.assertEqual(hashlib.sha256(retained.read_bytes()).hexdigest(), artifact["sha256"])
        self.assertEqual(manifest["source_revision"], self.revision)
        self.assertEqual(json.loads((output / "raw/instrumentation-status.json").read_text()),
                         {"status": "failed", "exit_code": 1})

    def test_failed_evidence_cannot_enter_the_complete_report(self):
        result = self.run_runner(instrumentation_status=1, write_output=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        output = Path(self.temporary.name) / "run"
        report = subprocess.run([
            "python3", "-I", str(HERE / "report.py"),
            str(output / "raw/additional-output/benchmarkData.json"),
            "--output", str(output), "--require-macro",
            "--evidence-manifest", str(output / "failed-evidence-manifest.json"),
        ], capture_output=True, text=True, check=False)
        self.assertEqual(report.returncode, 2)
        self.assertIn("benchmark_json", report.stderr)
        self.assertFalse((output / "report.json").exists())
        self.assertFalse((output / "report.md").exists())

    def test_failed_preservation_never_overwrites_on_a_retry(self):
        result = self.run_runner(instrumentation_status=1, write_output=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        output = Path(self.temporary.name) / "run"
        manifest_path = output / "failed-evidence-manifest.json"
        before = manifest_path.read_bytes()
        status_path = output / "instrumentation-status.json"
        status_path.write_text(json.dumps({"status": "failed", "exit_code": 124}))
        retry = subprocess.run(self.preservation_command, capture_output=True, text=True, check=False)
        self.assertEqual(retry.returncode, 2)
        self.assertIn("Refusing to mix failure diagnostics", retry.stderr)
        self.assertEqual(manifest_path.read_bytes(), before)
        self.assertTrue((output / "raw/additional-output/benchmarkData.json").is_file())

    def test_failed_preservation_rejects_mismatched_instrumentation_status(self):
        result = self.run_runner(instrumentation_status=1, write_output=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        output = Path(self.temporary.name) / "run"
        (output / "failed-evidence-manifest.json").unlink()
        shutil.rmtree(output / "raw")
        (output / "instrumentation-status.json").write_text(json.dumps({"status": "failed", "exit_code": 124}))
        rejected = subprocess.run(self.preservation_command, capture_output=True, text=True, check=False)
        self.assertEqual(rejected.returncode, 2)
        self.assertIn("does not match", rejected.stderr)
        self.assertFalse((output / "failed-evidence-manifest.json").exists())
        self.assertFalse((output / "raw").exists())
        self.assertFalse(any(output.glob(".failed-evidence-staging-*")))

    def test_failed_preservation_cannot_replace_existing_raw_evidence(self):
        result = self.run_runner(instrumentation_status=1, write_output=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        output = Path(self.temporary.name) / "run"
        (output / "failed-evidence-manifest.json").unlink()
        (output / "raw").rename(output / "retained-raw")
        (output / "raw").mkdir()
        (output / "raw/occupied").write_text("existing evidence")
        rejected = subprocess.run(self.preservation_command, capture_output=True, text=True, check=False)
        self.assertEqual(rejected.returncode, 2)
        self.assertIn("Refusing to publish over existing raw evidence", rejected.stderr)
        self.assertFalse((output / "failed-evidence-manifest.json").exists())
        self.assertEqual((output / "raw/occupied").read_text(), "existing evidence")
        self.assertTrue(any(output.glob(".failed-evidence-staging-*")))
        self.assertTrue((output / "retained-raw/additional-output/benchmarkData.json").is_file())

    def test_instrumentation_deadline_stays_failed_and_is_preserved(self):
        result = self.run_runner(instrumentation_status=124, write_output=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("reached its deadline", result.stderr)
        output = Path(self.temporary.name) / "run"
        manifest = json.loads((output / "failed-evidence-manifest.json").read_text())
        self.assertEqual(manifest["instrumentation"], {"exit_code": 124, "deadline_exceeded": True})
        self.assertEqual(manifest["status"], "failed")
        self.assertFalse((output / "report.json").exists())

    def test_failed_run_without_androidx_output_is_explicitly_incomplete(self):
        result = self.run_runner(instrumentation_status=1)
        self.assertEqual(result.returncode, 1, result.stderr)
        output = Path(self.temporary.name) / "run"
        manifest = json.loads((output / "failed-evidence-manifest.json").read_text())
        self.assertEqual({entry["kind"] for entry in manifest["artifacts"]},
                         {"environment", "instrumentation_status", "instrumentation_log"})
        self.assertEqual(manifest["status"], "failed")
        self.assertIs(manifest["complete"], False)


if __name__ == "__main__":
    unittest.main()
