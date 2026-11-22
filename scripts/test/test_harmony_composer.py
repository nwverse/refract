#!/usr/bin/env python3
"""Portable evidence-contract tests; these never emulate an SDK, device or IME."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "verify_harmony_composer.py"
SPEC = importlib.util.spec_from_file_location("verify_harmony_composer", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CommittedDraftEvidenceTests(unittest.TestCase):
    def case(self, codes: tuple[int, ...] = (1, 0), name: str | None = None) -> str:
        name = MODULE.SELECTED_CASE[1] if name is None else name
        return "".join(
            f"OHOS_REPORT_STATUS: class=GeneratedComposer\n"
            f"OHOS_REPORT_STATUS: current={index}\n"
            f"OHOS_REPORT_STATUS: id=JS\nOHOS_REPORT_STATUS: numtests=1\n"
            f"OHOS_REPORT_STATUS: stream=\nOHOS_REPORT_STATUS: test={name}\n"
            f"OHOS_REPORT_STATUS_CODE: {code}\n"
            for index, code in enumerate(codes, start=1)
        )

    def result(self, *, tests: int = 1, passed: int = 1, failure: int = 0,
               error: int = 0, ignored: int = 0, cases: str | None = None) -> str:
        cases = self.case() if cases is None else cases
        return (
            f"OHOS_REPORT_SUM: 1\nOHOS_REPORT_STATUS: class=GeneratedComposer\n"
            f"{cases}OHOS_REPORT_STATUS: class=GeneratedComposer\n"
            "OHOS_REPORT_STATUS: suiteconsuming=123\n"
            f"OHOS_REPORT_RESULT: stream=Tests run: {tests}, Failure: {failure}, Error: {error}, "
            f"Pass: {passed}, Ignore: {ignored}\nOHOS_REPORT_CODE: 0\n"
            "OHOS_REPORT_STATUS: taskconsuming=125\n"
        )

    def test_exact_observed_composer_success_is_the_only_limited_report(self) -> None:
        result = MODULE.validate_result(self.result())
        self.assertEqual(result["cases"], ["GeneratedComposer#committed_draft_focus_done_and_recreation"])

    def test_settings_success_cannot_substitute_for_composer_execution(self) -> None:
        settings = (Path(__file__).parent / "fixtures/harmony_hypium_1_0_25_representative.log").read_text(
            encoding="utf-8"
        )
        self.assertEqual(MODULE.SETTINGS.validate_result(settings)["passed"], 2)
        with self.assertRaises(MODULE.SETTINGS.VerificationError):
            MODULE.validate_result(settings)

    def test_wrong_failed_duplicate_or_incomplete_case_fails_closed(self) -> None:
        for cases in (
            self.case(name="different_case"), self.case(codes=(1,)), self.case(codes=(1, 1)),
            self.case(codes=(1, 0, 0)), self.case(codes=(0,)), "",
        ):
            with self.subTest(cases=cases), self.assertRaises(MODULE.SETTINGS.VerificationError):
                MODULE.validate_result(self.result(cases=cases))

    def test_duplicate_conflicting_and_unknown_suite_starts_fail_closed(self) -> None:
        start = "OHOS_REPORT_SUM: 1\nOHOS_REPORT_STATUS: class=GeneratedComposer\n"
        for prefix in (
            start,
            "OHOS_REPORT_SUM: 1\nOHOS_REPORT_STATUS: class=GeneratedSettingsRender\n",
            "OHOS_REPORT_SUM: 1\nOHOS_REPORT_STATUS: class=UnknownSuite\n",
            "OHOS_REPORT_SUM: 2\nOHOS_REPORT_STATUS: class=GeneratedComposer\n",
        ):
            with self.subTest(prefix=prefix), \
                 self.assertRaises(MODULE.SETTINGS.VerificationError, msg="duplicate suite start must be rejected"):
                MODULE.validate_result(self.result().replace(start, prefix + start, 1))

    def test_summary_and_terminal_cannot_hide_an_unsuccessful_run(self) -> None:
        for result in (
            self.result(tests=0, passed=0, cases=""), self.result(failure=1, passed=0),
            self.result(error=1, passed=0), self.result(ignored=1, passed=0),
            self.result() + self.result(),
            self.result().replace("OHOS_REPORT_CODE: 0", "OHOS_REPORT_CODE: -1"),
            self.result().replace("OHOS_REPORT_CODE: 0\n", ""),
            self.result().replace("OHOS_REPORT_STATUS: taskconsuming=125\n", ""),
        ):
            with self.subTest(result=result), self.assertRaises(MODULE.SETTINGS.VerificationError):
                MODULE.validate_result(result)

    def test_rejects_an_unsafe_target_before_running_tools(self) -> None:
        with tempfile.TemporaryDirectory(prefix="refract-harmony-composer-test.") as temporary:
            output = Path(temporary) / "evidence"
            with mock.patch.object(MODULE.subprocess, "run") as run:
                status = MODULE.main([
                    "--target", "invalid;target", "--target-class", "device",
                    "--target-description", "owner supplied target", "--app-hap", str(SCRIPT),
                    "--test-hap", str(SCRIPT), "--output", str(output),
                ])
            self.assertEqual(status, 2)
            self.assertFalse(output.exists())
            run.assert_not_called()

    def test_missing_prerequisites_do_not_run_a_build_or_device(self) -> None:
        with tempfile.TemporaryDirectory(prefix="refract-harmony-composer-test.") as temporary:
            output = Path(temporary) / "evidence"
            with mock.patch.object(MODULE.SETTINGS, "source_revision", return_value="a" * 40), \
                 mock.patch.object(MODULE.SETTINGS.PREFLIGHT, "preflight", return_value=({}, ["SDK absent"])), \
                 mock.patch.object(MODULE.subprocess, "run") as run:
                status = MODULE.main([
                    "--target", "owned-target", "--target-class", "emulator",
                    "--target-description", "owner supplied target", "--app-hap", str(SCRIPT),
                    "--test-hap", str(SCRIPT), "--output", str(output),
                ])
            self.assertEqual(status, 1)
            run.assert_not_called()
            metadata = json.loads((output / "metadata.json").read_text(encoding="utf-8"))
            self.assertEqual(metadata["status"], "failed-or-blocked")
            self.assertFalse(metadata["imeVerified"])

    def test_selected_suite_registers_the_matching_host_only(self) -> None:
        ability = (
            MODULE.SETTINGS.EXAMPLE / "entry/src/ohosTest/ets/testability/TestAbility.ets"
        ).read_text(encoding="utf-8")
        composer = ability.split("selectedSuite === 'GeneratedComposer'", 1)[1].split("} else", 1)[0]
        self.assertIn("testability/GeneratedComposerHost", composer)
        self.assertIn("generatedComposerTests();", composer)
        self.assertNotIn("generatedSettingsTests();", composer)
        self.assertNotIn("generatedSettingsRenderTests();", composer)
        self.assertNotIn("GeneratedSettingsHost", composer)
        settings = ability.split("selectedSuite === 'GeneratedSettingsRender'", 1)[1].split("} else", 1)[0]
        self.assertIn("generatedSettingsRenderTests();", settings)
        self.assertNotIn("generatedComposerTests();", settings)
        self.assertNotIn("generatedSettingsTests();", ability)
        self.assertIn("abilityDelegatorRegistry.getArguments().parameters", ability)
        self.assertIn("parameters['refractSuite']", ability)
        self.assertIn("parameters['class']", ability)
        self.assertIn("filteredSuite !== selectedSuite", ability)
        self.assertIn("Unknown or missing native verification suite", ability)
        self.assertIn("Native verification suite parameters are missing or contradictory", ability)
        self.assertLess(ability.index("filteredSuite !== selectedSuite"), ability.index("Hypium.hypiumTest("))
        native_test = (
            MODULE.SETTINGS.EXAMPLE / "entry/src/ohosTest/ets/test/GeneratedComposer.test.ets"
        ).read_text(encoding="utf-8")
        self.assertIn(f"describe('{MODULE.SELECTED_CASE[0]}'", native_test)
        self.assertIn(f"it('{MODULE.SELECTED_CASE[1]}'", native_test)

    def test_unknown_or_mismatched_suite_command_parameters_fail_closed(self) -> None:
        selected = ("class", "GeneratedComposer")
        for parameters in (
            (selected, selected),
            (("refractSuite", "GeneratedComposer"), ("refractSuite", "GeneratedComposer")),
            (selected, ("refractSuite", "GeneratedSettingsRender")),
            (selected, ("refractSuite", "UnknownSuite")),
            (selected,), (("class", "UnknownSuite"), ("refractSuite", "UnknownSuite")),
        ):
            with self.subTest(parameters=parameters), self.assertRaises(MODULE.SETTINGS.VerificationError):
                MODULE.SETTINGS.selected_suite(parameters)
        for suite in ("UnknownSuite", "", "GeneratedSettings"):
            with self.subTest(suite=suite), self.assertRaises(MODULE.SETTINGS.VerificationError):
                MODULE.SETTINGS.selected_suite_command(["hdc", "-t", "owned-target"], suite)
        command = MODULE.SETTINGS.selected_suite_command(["hdc"], MODULE.SELECTED_CASE[0])
        for selector in ("class", "refractSuite"):
            self.assertEqual(command.count(selector), 1)
            self.assertEqual(command[command.index(selector) + 1], MODULE.SELECTED_CASE[0])
        for key in ("refractSuite", "class"):
            self.assertIn(f"parameters['{key}']", MODULE.SETTINGS.EXAMPLE.joinpath(
                "entry/src/ohosTest/ets/testability/TestAbility.ets").read_text(encoding="utf-8"))

    def run_complete_state_machine(self, temporary: str, native_output: str) -> tuple[int, dict[str, object]]:
        output = Path(temporary) / "private-evidence"
        commands: list[list[str]] = []

        def command_result(command: list[str], log_path: Path, **kwargs: object) -> mock.Mock:
            commands.append(command)
            text = "26.0.0\n" if "--version" in command else native_output if "test" in command else ""
            return mock.Mock(stdout=text, returncode=0)

        with mock.patch.object(MODULE.SETTINGS, "source_revision", return_value="a" * 40), \
             mock.patch.object(MODULE.SETTINGS.PREFLIGHT, "preflight", return_value=({"devecocli": SCRIPT}, [])), \
             mock.patch.object(MODULE.shutil, "which", return_value="/authorized/hdc"), \
             mock.patch.object(MODULE.SETTINGS, "execute", side_effect=command_result):
            status = MODULE.main([
                "--target", "owned-target", "--target-class", "emulator",
                "--target-description", "owner supplied target", "--app-hap", str(SCRIPT),
                "--test-hap", str(SCRIPT), "--output", str(output),
            ])
        metadata = json.loads((output / "metadata.json").read_text(encoding="utf-8"))
        test_commands = [command for command in commands if "shell" in command and "test" in command]
        self.assertEqual(len(test_commands), 1)
        test_command = test_commands[0]
        self.assertIn("GeneratedComposer", test_command)
        self.assertIn("refractSuite", test_command)
        self.assertNotIn("GeneratedSettingsRender", test_command)
        return status, metadata

    def test_mocked_execution_never_becomes_ime_or_render_verification(self) -> None:
        with tempfile.TemporaryDirectory(prefix="refract-harmony-composer-test.") as temporary:
            status, metadata = self.run_complete_state_machine(temporary, self.result())
        self.assertEqual(status, 0)
        self.assertEqual(metadata["status"], "native-committed-draft-executed-ime-unverified")
        self.assertFalse(metadata["imeVerified"])
        self.assertFalse(metadata["renderVerified"])
        self.assertFalse(metadata["performanceMeasured"])
        self.assertFalse(metadata["buildSkipped"])

    def test_missing_tool_or_settings_result_still_writes_a_failed_report(self) -> None:
        for native_output in ("", self.result(cases=self.case(name="wrong_case"))):
            with self.subTest(native_output=native_output), \
                 tempfile.TemporaryDirectory(prefix="refract-harmony-composer-test.") as temporary:
                status, metadata = self.run_complete_state_machine(temporary, native_output)
            self.assertEqual(status, 1)
            self.assertEqual(metadata["status"], "failed-or-blocked")
            self.assertFalse(metadata["imeVerified"])
            self.assertNotIn("nativeTests", metadata)


if __name__ == "__main__":
    unittest.main()
