#!/usr/bin/env python3
"""Portable checks for the HarmonyOS rendering evidence gate; no fake native tools."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "verify_harmony_settings.py"
SPEC = importlib.util.spec_from_file_location("verify_harmony_settings", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
with mock.patch.object(sys, "path", [str(SCRIPT.parent), *sys.path]):
    SPEC.loader.exec_module(MODULE)


class RenderingEvidenceTests(unittest.TestCase):
    def result(self, tests: int = 3, failure: int = 0, error: int = 0, passed: int = 3, ignored: int = 0) -> str:
        return (
            f"OHOS_REPORT_RESULT: stream=Tests run: {tests}, Failure: {failure}, Error: {error}, "
            f"Pass: {passed}, Ignore: {ignored}\nOHOS_REPORT_CODE: 0\n"
        )

    def test_complete_native_summary_is_required(self) -> None:
        self.assertEqual(MODULE.validate_result(self.result())["passed"], 3)

    def test_overall_zero_cannot_hide_failures_errors_or_ignored_tests(self) -> None:
        for output in (
            self.result(failure=1, passed=2), self.result(error=1, passed=2),
            self.result(ignored=1, passed=2), self.result(tests=0, passed=0),
            "OHOS_REPORT_CODE: 0\n", self.result() + self.result(),
        ):
            with self.subTest(output=output), self.assertRaises(MODULE.VerificationError):
                MODULE.validate_result(output)

    def test_native_test_target_selects_real_generated_host_and_controls(self) -> None:
        root = MODULE.EXAMPLE / "entry/src/ohosTest"
        host = (root / "ets/testability/GeneratedSettingsHost.ets").read_text(encoding="utf-8")
        tests = (root / "ets/test/GeneratedSettingsRender.test.ets").read_text(encoding="utf-8")
        ability = (root / "ets/testability/TestAbility.ets").read_text(encoding="utf-8")
        self.assertIn("../../../main/ets/generated/SettingsScreen", host)
        self.assertIn("SettingsScreen({", host)
        self.assertNotIn("HandWrittenSettingsScreen", host)
        for call in ("ON.type('Toggle')", "ON.type('TextInput')", "ON.type('List')",
                     "isCheckable()", "checked(value)", "scrollSearch", "screenCap", "dumpLayout"):
            self.assertIn(call, tests)
        self.assertIn("testability/GeneratedSettingsHost", ability)
        self.assertIn("COLOR_MODE_LIGHT", ability)
        self.assertIn("COLOR_MODE_DARK", host)
        self.assertNotIn("performance", tests.lower())

    def test_missing_authorized_inputs_do_not_run_a_build_or_device(self) -> None:
        with tempfile.TemporaryDirectory(prefix="refract-harmony-render-test.") as temporary:
            output = Path(temporary) / "private-evidence"
            with mock.patch.object(MODULE, "source_revision", return_value="a" * 40), \
                 mock.patch.object(MODULE.PREFLIGHT, "preflight", return_value=({}, ["authorized SDK absent"])), \
                 mock.patch.object(MODULE.subprocess, "run") as run:
                status = MODULE.main([
                    "--target", "owned-target", "--target-class", "emulator",
                    "--target-description", "owner-supplied target",
                    "--app-hap", str(SCRIPT), "--test-hap", str(SCRIPT), "--output", str(output),
                ])
            self.assertEqual(status, 1)
            run.assert_not_called()
            metadata = (output / "metadata.json").read_text(encoding="utf-8")
            self.assertIn('"renderVerified": false', metadata)
            self.assertIn('"status": "failed-or-blocked"', metadata)

    def test_invalid_artifact_path_still_writes_a_blocked_report(self) -> None:
        with tempfile.TemporaryDirectory(prefix="refract-harmony-render-test.") as temporary:
            output = Path(temporary) / "private-evidence"
            with mock.patch.object(MODULE, "source_revision", return_value="a" * 40), \
                 mock.patch.object(MODULE.subprocess, "run") as run:
                status = MODULE.main([
                    "--target", "owned-target", "--target-class", "device",
                    "--target-description", "owner-supplied target",
                    "--app-hap", str(Path(temporary) / "absent.hap"), "--test-hap", str(SCRIPT),
                    "--output", str(output),
                ])
            self.assertEqual(status, 1)
            run.assert_not_called()
            self.assertIn('"status": "failed-or-blocked"', (output / "metadata.json").read_text(encoding="utf-8"))

    def test_rejects_an_implicit_or_unsafe_target(self) -> None:
        result = subprocess.run(
            [sys.executable, "-I", str(SCRIPT), "--target", "invalid;target",
             "--target-class", "device", "--target-description", "owner supplied",
             "--app-hap", str(SCRIPT), "--test-hap", str(SCRIPT), "--output", "/tmp/unused-render-evidence"],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("target", result.stderr)


if __name__ == "__main__":
    unittest.main()
