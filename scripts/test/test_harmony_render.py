#!/usr/bin/env python3
"""Portable checks for the HarmonyOS rendering evidence gate; no fake native tools."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Sequence
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
    def case_result(self, suite: str, name: str, codes: tuple[int, ...] = (1, 0)) -> str:
        records = []
        for index, code in enumerate(codes, start=1):
            records.append(
                f"OHOS_REPORT_STATUS: class={suite}\nOHOS_REPORT_STATUS: current={index}\n"
                f"OHOS_REPORT_STATUS: id=JS\nOHOS_REPORT_STATUS: numtests=2\n"
                f"OHOS_REPORT_STATUS: stream=\nOHOS_REPORT_STATUS: test={name}\n"
                f"OHOS_REPORT_STATUS_CODE: {code}\n"
            )
        return "".join(records)

    def result(self, tests: int = 2, failure: int = 0, error: int = 0, passed: int = 2,
               ignored: int = 0, cases: str | None = None, code: str = "0", total_tests: int = 2,
               suites: bool = True) -> str:
        if cases is None:
            cases = "".join(self.case_result(suite, name) for suite, name in MODULE.EXPECTED_CASES)
        cases = cases.replace("numtests=2", f"numtests={total_tests}")
        prefix = suffix = ""
        if suites:
            prefix = "OHOS_REPORT_SUM: 2\nOHOS_REPORT_STATUS: class=GeneratedSettingsRender\n"
            suffix = "OHOS_REPORT_STATUS: class=GeneratedSettingsRender\nOHOS_REPORT_STATUS: suiteconsuming=123\n"
        return (
            f"{prefix}{cases}{suffix}OHOS_REPORT_RESULT: stream=Tests run: {tests}, Failure: {failure}, "
            f"Error: {error}, Pass: {passed}, Ignore: {ignored}\nOHOS_REPORT_CODE: {code}\n"
            "OHOS_REPORT_STATUS: taskconsuming=125\n"
        )

    def test_pinned_representative_suite_case_and_task_records_pass(self) -> None:
        output = (Path(__file__).parent / "fixtures/harmony_hypium_1_0_25_representative.log").read_text(
            encoding="utf-8"
        )
        result = MODULE.validate_result(output)
        self.assertEqual(result["passed"], 2)
        self.assertEqual(result["cases"], [f"{suite}#{name}" for suite, name in MODULE.EXPECTED_CASES])

    def test_native_case_report_serializes_observed_successes(self) -> None:
        with mock.patch.object(MODULE, "format_observed_cases", side_effect=lambda cases: [
            f"observed:{suite}#{name}" for suite, name in cases
        ]):
            result = MODULE.validate_result(self.result())
        self.assertEqual(result["cases"], [f"observed:{suite}#{name}" for suite, name in MODULE.EXPECTED_CASES])

    def test_overall_zero_cannot_hide_failures_errors_or_ignored_tests(self) -> None:
        wrong_suite = self.case_result("GeneratedSettings", "generated_model_interface_accepts_a_typed_native_implementation")
        light, dark = MODULE.EXPECTED_CASES
        for output in (
            self.result(failure=1, passed=1), self.result(error=1, passed=1),
            self.result(ignored=1, passed=1), self.result(tests=0, passed=0, cases=""),
            self.result(tests=3, passed=3, cases=self.result(suites=False) + self.case_result("Other", "extra")),
            self.result(cases=self.case_result(*light) + self.case_result("Other", dark[1])),
            self.result(cases=self.case_result(*light) + self.case_result(*dark, codes=(1, 1))),
            self.result(cases=self.case_result(*light, codes=(1, 0, 0)) + self.case_result(*dark)),
            self.result(cases=self.result(suites=False).split("OHOS_REPORT_RESULT:")[0] + wrong_suite),
            self.result(code=""), self.result() + self.result(),
        ):
            with self.subTest(output=output), self.assertRaises(MODULE.VerificationError):
                MODULE.validate_result(output)

    def test_suite_lifecycle_records_are_required_and_distinct(self) -> None:
        valid = self.result()
        suite_start = "OHOS_REPORT_SUM: 2\nOHOS_REPORT_STATUS: class=GeneratedSettingsRender\n"
        suite_end = "OHOS_REPORT_STATUS: class=GeneratedSettingsRender\nOHOS_REPORT_STATUS: suiteconsuming=123\n"
        for output in (
            self.result(suites=False),
            valid.replace(suite_start, suite_start + suite_start, 1),
            valid.replace(suite_end, suite_end + suite_end, 1),
            valid.replace(suite_start, "OHOS_REPORT_STATUS: class=GeneratedSettingsRender\n", 1),
            valid.replace(suite_end, "OHOS_REPORT_STATUS: class=GeneratedSettingsRender\n", 1),
        ):
            with self.subTest(output=output), self.assertRaises(MODULE.VerificationError):
                MODULE.validate_result(output)

    def test_mixed_duplicate_or_nonzero_terminal_codes_fail_closed(self) -> None:
        terminal = "OHOS_REPORT_CODE: 0"
        for output in (
            self.result().replace(terminal, "OHOS_REPORT_CODE: -1\nOHOS_REPORT_CODE: 0"),
            self.result().replace(terminal, "OHOS_REPORT_CODE: 0\nOHOS_REPORT_CODE: -1"),
            self.result().replace(terminal, "OHOS_REPORT_CODE: -1"),
            self.result().replace(terminal, "OHOS_REPORT_CODE: 0\nOHOS_REPORT_CODE: 0"),
            self.result().replace("OHOS_REPORT_STATUS: taskconsuming=125\n", ""),
        ):
            with self.subTest(output=output), self.assertRaises(MODULE.VerificationError):
                MODULE.validate_result(output)

    def test_atomic_records_cannot_be_spliced_or_reordered(self) -> None:
        valid = self.result()
        light, dark = MODULE.EXPECTED_CASES
        case_one = self.case_result(*light)
        case_two = self.case_result(*dark)
        suite_start = "OHOS_REPORT_SUM: 2\nOHOS_REPORT_STATUS: class=GeneratedSettingsRender\n"
        suite_end = "OHOS_REPORT_STATUS: class=GeneratedSettingsRender\nOHOS_REPORT_STATUS: suiteconsuming=123\n"
        for output in (
            valid.replace(case_one, self.case_result(*light, codes=(1,)), 1),
            valid.replace(case_two, self.case_result(*dark, codes=(0,)), 1),
            valid.replace("OHOS_REPORT_STATUS_CODE: 1\n", "", 1),
            valid.replace("OHOS_REPORT_CODE: 0\n", ""),
            valid.replace("OHOS_REPORT_STATUS: taskconsuming=125\n", "OHOS_REPORT_STATUS: class=GeneratedSettingsRender\n"),
            valid.replace(suite_end, suite_end + "OHOS_REPORT_STATUS: class=GeneratedSettingsRender\n"),
            valid.replace(suite_start, "OHOS_REPORT_STATUS: class=GeneratedSettingsRender\nOHOS_REPORT_SUM: 2\n", 1),
        ):
            with self.subTest(output=output), self.assertRaises(MODULE.VerificationError):
                MODULE.validate_result(output)

    def test_early_terminal_and_task_completion_fail_closed(self) -> None:
        fixture = (Path(__file__).parent / "fixtures/harmony_hypium_1_0_25_representative.log").read_text(
            encoding="utf-8"
        )
        terminal = "OHOS_REPORT_CODE: 0\n"
        task_done = "OHOS_REPORT_STATUS: taskconsuming=6112\n"
        second_case = (
            "OHOS_REPORT_STATUS: class=GeneratedSettingsRender\n"
            "OHOS_REPORT_STATUS: current=2\n"
        )
        second_case += fixture.split(second_case, 1)[1].split("OHOS_REPORT_STATUS_CODE: 1\n", 1)[0]
        second_case += "OHOS_REPORT_STATUS_CODE: 1\n"
        reordered = fixture.replace(terminal + task_done, "").replace(
            second_case, terminal + task_done + second_case, 1
        )
        self.assertIn(terminal + task_done + second_case, reordered)
        with self.assertRaises(MODULE.VerificationError):
            MODULE.validate_result(reordered)

    def test_native_test_target_selects_real_generated_host_and_controls(self) -> None:
        root = MODULE.EXAMPLE / "entry/src/ohosTest"
        host = (root / "ets/testability/GeneratedSettingsHost.ets").read_text(encoding="utf-8")
        tests = (root / "ets/test/GeneratedSettingsRender.test.ets").read_text(encoding="utf-8")
        ability = (root / "ets/testability/TestAbility.ets").read_text(encoding="utf-8")
        self.assertIn("../../../main/ets/generated/SettingsScreen", host)
        self.assertIn("SettingsScreen({", host)
        for name in MODULE.EXPECTED_CASES:
            self.assertIn(f"'{name[1]}'", tests)
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

    def test_mocked_complete_execution_still_requires_human_inspection(self) -> None:
        # This exercises only the local evidence state machine, not an SDK or device.
        with tempfile.TemporaryDirectory(prefix="refract-harmony-render-test.") as temporary:
            root = Path(temporary)
            output = root / "private-evidence"

            def command_result(command: Sequence[str], log_path: Path, **kwargs: object) -> mock.Mock:
                if command[:2] == ["hdc", "-t"] and "recv" in command:
                    destination = Path(command[-1])
                    if destination.suffix == ".png":
                        destination.write_bytes(b"\x89PNG\r\n\x1a\nportable-test-placeholder")
                    else:
                        destination.write_text("{}", encoding="utf-8")
                output_text = "26.0.0\n" if "--version" in command else ""
                if "test" in command:
                    output_text = self.result()
                return mock.Mock(stdout=output_text, returncode=0)

            with mock.patch.object(MODULE, "source_revision", return_value="a" * 40), \
                 mock.patch.object(MODULE.PREFLIGHT, "preflight", return_value=({"devecocli": SCRIPT}, [])), \
                 mock.patch.object(MODULE.shutil, "which", return_value="/authorized/hdc"), \
                 mock.patch.object(MODULE, "execute", side_effect=command_result) as execute:
                status = MODULE.main([
                    "--target", "owned-target", "--target-class", "emulator",
                    "--target-description", "owner-supplied target",
                    "--app-hap", str(SCRIPT), "--test-hap", str(SCRIPT), "--output", str(output),
                ])
            self.assertEqual(status, 0)
            commands = [call.args[0] for call in execute.call_args_list]
            test_commands = [command for command in commands if "shell" in command and "test" in command]
            self.assertEqual(len(test_commands), 1)
            self.assertIn("refractSuite", test_commands[0])
            self.assertIn("GeneratedSettingsRender", test_commands[0])
            self.assertNotIn("GeneratedComposer", test_commands[0])
            metadata = (output / "metadata.json").read_text(encoding="utf-8")
            self.assertIn('"renderVerified": false', metadata)
            self.assertIn('"status": "executed-awaiting-human-capture-inspection"', metadata)

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
