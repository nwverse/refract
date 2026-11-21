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
        (self.bench / "benchmark/build/outputs").mkdir(parents=True)
        shutil.copy(HERE / "run-emulator.sh", self.bench / "run-emulator.sh")
        (self.bench / "gradlew").write_text(
            "#!/usr/bin/env bash\n"
            "printf '%s\\n' \"$@\" > \"$RUNNER_CAPTURE_DIR/gradle-arguments.txt\"\n"
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
        subprocess.run(["git", "-C", str(self.root), "add", "bench/android/run-emulator.sh",
                        "bench/android/gradlew", "bench/android/generate-and-compile.sh",
                        "bench/android/probe_target.py", "bench/android/collect_results.py",
                        "bench/android/report.py", "platform-tools/adb"], check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=Benchmark Fixture",
                        "-c", "user.email=me@example.com", "commit", "--quiet", "-m", "Synthetic runner fixture"],
                       check=True)
        self.revision = subprocess.check_output(["git", "-C", str(self.root), "rev-parse", "HEAD"], text=True).strip()
        self.capture = Path(self.temporary.name) / "capture"
        self.capture.mkdir()

    def run_runner(self, dirty=False, instrumentation_status=0):
        output = Path(self.temporary.name) / "run"
        environment = dict(os.environ,
                           GIT_AUTHOR_NAME="Benchmark Fixture", GIT_AUTHOR_EMAIL="me@example.com",
                           GIT_COMMITTER_NAME="Benchmark Fixture", GIT_COMMITTER_EMAIL="me@example.com",
                           JAVA_HOME=os.environ.get("JAVA_HOME", "/usr"),
                           ANDROID_HOME=str(self.root),
                           RUNNER_CAPTURE_DIR=str(self.capture), RUNNER_SOURCE=str(self.root),
                           RUNNER_DIRTY="1" if dirty else "0",
                           RUNNER_INSTRUMENTATION_STATUS=str(instrumentation_status))
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

    def test_instrumentation_failure_cannot_pass(self):
        result = self.run_runner(instrumentation_status=1)
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.capture / "report-arguments.json").exists())
        self.assertEqual(json.loads((Path(self.temporary.name) / "run/instrumentation-status.json").read_text()),
                         {"status": "failed", "exit_code": 1})


if __name__ == "__main__":
    unittest.main()
