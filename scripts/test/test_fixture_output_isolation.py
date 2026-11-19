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

        with tempfile.TemporaryDirectory(prefix="refract-fixture-isolation-test-") as temporary:
            checkout = Path(temporary)
            module.ROOT = checkout
            with mock.patch.object(module, "stage_resources", create=True, side_effect=stage_expected), \
                 mock.patch.object(module.subprocess, "run", side_effect=generate):
                module.regenerate_and_stage("benchmark-settings")
            self.assertIsNotNone(observed.get("cwd"))
            self.assertEqual(Path(observed["cwd"]), Path(observed["android"]).parent)
            self.assertEqual(Path(observed["cwd"]), Path(observed["harmony"]).parent)
            self.assertFalse((checkout / "generated").exists())

    def test_cross_file_staging_uses_the_same_isolated_working_directory(self):
        script = Path(__file__).resolve().parents[1] / "check_fixture_compilation.py"
        spec = importlib.util.spec_from_file_location("check_fixture_compilation_for_cross_file_test", script)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        fixture_dir = module.FIXTURES_ROOT / "cross-file-child-view"
        inputs = sorted(path for path in fixture_dir.glob("*.swift") if path.name != "Input.swift")
        observed = {}

        def generate(arguments, cwd, check):
            observed["cwd"] = cwd
            observed["android"] = arguments[arguments.index("--android-out") + 1]
            observed["harmony"] = arguments[arguments.index("--harmony-out") + 1]
            Path(observed["android"]).mkdir(parents=True)
            for input_path in inputs:
                (Path(observed["android"]) / f"{input_path.stem}.kt").write_bytes(
                    (fixture_dir / f"Expected.{input_path.stem}.kt").read_bytes())
            self.assertNotEqual(cwd, module.ROOT)
            return subprocess.CompletedProcess(arguments, 0)

        with tempfile.TemporaryDirectory(prefix="refract-cross-file-isolation-test-") as temporary:
            module.ROOT = Path(temporary)
            module.STAGING_VALUES = module.ROOT / "staged/values"
            with mock.patch.object(module, "stage_generated"), \
                 mock.patch.object(module, "merge_strings"), \
                 mock.patch.object(module.subprocess, "run", side_effect=generate):
                module.regenerate_and_stage_multiple(
                    "cross-file-child-view", fixture_dir, inputs,
                    fixture_dir / "refract.json", fixture_dir / "values/strings.xml")
            self.assertEqual(Path(observed["cwd"]), Path(observed["android"]).parent)
            self.assertEqual(Path(observed["cwd"]), Path(observed["harmony"]).parent)
            self.assertFalse((module.ROOT / "generated").exists())

    def test_fixture_test_cleanup_preserves_tracked_native_tests(self):
        script = Path(__file__).resolve().parents[1] / "check_fixture_compilation.py"
        spec = importlib.util.spec_from_file_location("check_fixture_compilation_for_test_cleanup", script)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)

        with tempfile.TemporaryDirectory(prefix="refract-fixture-test-cleanup-") as temporary:
            checkout = Path(temporary)
            (checkout / "examples/android/fixture-compile-manifest.txt").parent.mkdir(parents=True)
            (checkout / "examples/android/fixture-compile-manifest.txt").write_text(
                "modal-native-host\nmodal-sheet-state\n", encoding="utf-8")
            module.ROOT = checkout
            module.MANIFEST = checkout / "examples/android/fixture-compile-manifest.txt"
            module.STAGING_TEST = checkout / "examples/android/fixtures/src/test/java/example/native"
            tracked = module.STAGING_TEST / "example/native/NavigationDeepRestorationTest.kt"
            tracked.parent.mkdir(parents=True)
            tracked.write_text("package example.native\nclass NavigationDeepRestorationTest\n", encoding="utf-8")
            stale = module.STAGING_TEST / "example/native/NativeModalHostTest.kt"
            stale.write_text("stale", encoding="utf-8")
            regenerated = []

            with mock.patch.object(module, "regenerate_and_stage",
                                   side_effect=lambda fixture: regenerated.append(fixture)):
                self.assertEqual(module.main(), 0)

            self.assertEqual(tracked.read_text(encoding="utf-8"),
                             "package example.native\nclass NavigationDeepRestorationTest\n")
            self.assertFalse(stale.exists())
            self.assertEqual(regenerated, ["modal-native-host", "modal-sheet-state"])


if __name__ == "__main__":
    unittest.main()
