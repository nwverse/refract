#!/usr/bin/env python3
"""Test the HarmonyOS preflight without using or emulating a vendor compiler."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "check_harmony_toolchain.py"
SPEC = importlib.util.spec_from_file_location("check_harmony_toolchain", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class HarmonyPreflightTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="refract-harmony-preflight-test.")
        self.root = Path(self.temporary.name)
        self.tools = self.root / "authorized/command-line-tools"
        for relative in ("bin", "tool/node/bin"):
            (self.tools / relative).mkdir(parents=True)
        self.environment = {
            "PATH": str(self.root / "empty-path"),
            "COMMANDLINE_TOOL_DIR": str(self.root / "authorized"),
        }
        (self.root / "empty-path").mkdir()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def executable(self, name: str, directory: str = "bin") -> Path:
        path = self.tools / directory / name
        path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        path.chmod(stat.S_IRWXU)
        return path

    def complete_tools(self) -> dict[str, Path]:
        return {
            "devecocli": self.executable("devecocli"),
            "ohpm": self.executable("ohpm"),
            "java": self.executable("java", "tool/node/bin"),
        }

    def test_absent_local_tools_report_a_blocker_without_building(self) -> None:
        (self.root / "empty-path" / "devecocli").write_text("not executable\n", encoding="utf-8")
        with mock.patch.object(MODULE.subprocess, "run") as run:
            status = MODULE.main(["--check-only"], self.environment)
        self.assertEqual(status, 2)
        run.assert_not_called()

    def test_executable_file_is_not_accepted_as_the_vendor_cli(self) -> None:
        tools = self.complete_tools()
        tools["devecocli"].unlink()
        (self.root / "empty-path" / "devecocli").write_text("unverified placeholder\n", encoding="utf-8")
        tools, errors = MODULE.preflight(self.environment)
        self.assertNotIn("devecocli", tools)
        self.assertTrue(any("BLOCKED" in error for error in errors))

    def test_check_only_does_not_call_the_compiler(self) -> None:
        self.complete_tools()
        with mock.patch.object(MODULE.subprocess, "run") as run:
            status = MODULE.main(["--check-only"], self.environment)
        self.assertEqual(status, 0)
        run.assert_not_called()

    def test_real_application_build_uses_the_checked_in_example(self) -> None:
        tools = self.complete_tools()
        completed = subprocess.CompletedProcess([], 0)
        with mock.patch.object(MODULE.subprocess, "run", return_value=completed) as run:
            status = MODULE.main([], self.environment)
        self.assertEqual(status, 0)
        run.assert_called_once_with(
            [str(tools["devecocli"]), "build"],
            cwd=MODULE.EXAMPLE,
            env=self.environment,
            check=False,
        )

    def test_native_test_target_is_separate_and_propagates_failure(self) -> None:
        tools = self.complete_tools()
        completed = subprocess.CompletedProcess([], 1)
        with mock.patch.object(MODULE.subprocess, "run", return_value=completed) as run:
            status = MODULE.main(["--native-test-target"], self.environment)
        self.assertEqual(status, 1)
        self.assertEqual(
            run.call_args.args[0],
            [str(tools["devecocli"]), "build", "--modules", "entry@ohosTest"],
        )

    def test_java_home_is_an_existing_executable_not_an_environment_label(self) -> None:
        self.complete_tools()
        self.environment["JAVA_HOME"] = str(self.root / "missing-jdk")
        _, errors = MODULE.preflight(self.environment)
        self.assertIn("JAVA_HOME/bin/java is not an executable file", errors)

    def test_relative_script_invocation_needs_no_current_directory_import(self) -> None:
        result = subprocess.run(
            [sys.executable, "-I", str(SCRIPT), "--check-only"],
            cwd=self.root,
            env={"PATH": os.defpath},
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("BLOCKED", result.stderr)


if __name__ == "__main__":
    unittest.main()
