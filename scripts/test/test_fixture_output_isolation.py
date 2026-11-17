#!/usr/bin/env python3
"""Regression: fixture staging must not leak relative mapping outputs into the checkout."""

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


class FixtureOutputIsolationTest(unittest.TestCase):
    def test_relative_output_directory_uses_the_isolated_working_directory(self):
        script = Path(__file__).resolve().parents[1] / "check_fixture_compilation.py"
        spec = importlib.util.spec_from_file_location("check_fixture_compilation_for_test", script)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        observed = {}

        def stage_expected(_fixture):
            return None

        def generate(arguments, cwd, check):
            observed["cwd"] = cwd
            observed["android"] = arguments[arguments.index("--android-out") + 1]
            observed["harmony"] = arguments[arguments.index("--harmony-out") + 1]
            if not Path(observed["android"]).is_absolute() or not Path(observed["harmony"]).is_absolute():
                raise AssertionError("Staged native output directories must be absolute")
            Path(observed["android"]).mkdir(parents=True)
            (Path(observed["android"]) / "Input.kt").write_bytes(
                (module.FIXTURES_ROOT / "benchmark-settings/Expected.kt").read_bytes())
            self.assertNotEqual(cwd, module.ROOT)
            self.assertFalse((module.ROOT / "generated").exists())
            return subprocess.CompletedProcess(arguments, 0)

        with mock.patch.object(module, "stage_resources", create=True, side_effect=stage_expected), \
             mock.patch.object(module.subprocess, "run", side_effect=generate):
            module.regenerate_and_stage("benchmark-settings")
        self.assertIsNotNone(observed.get("cwd"))
        self.assertFalse((module.ROOT / "generated").exists())


if __name__ == "__main__":
    unittest.main()
