#!/usr/bin/env python3
"""Negative tests for static Harmony host contracts; never a fake native test."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "check_harmony_text_input.py"
SPEC = importlib.util.spec_from_file_location("check_harmony_text_input", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class HarmonyTextInputSourceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="refract-harmony-input-test.")
        self.root = Path(self.temporary.name)
        for relative in MODULE.REQUIRED_PATHS:
            source = MODULE.ROOT / relative
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def replace(self, relative: Path, old: str, new: str) -> None:
        path = self.root / relative
        source = path.read_text(encoding="utf-8")
        self.assertIn(old, source)
        path.write_text(source.replace(old, new, 1), encoding="utf-8")

    def replace_both_hosts(self, old: str, new: str) -> None:
        for relative in (MODULE.HOST, MODULE.CANONICAL_HOST):
            self.replace(relative, old, new)

    def assert_rejected(self, message: str) -> None:
        with self.assertRaises(MODULE.SourceContractError) as failure:
            MODULE.validate_source_contract(self.root)
        self.assertIn(message, str(failure.exception))

    def test_checked_in_sources_satisfy_the_static_boundary(self) -> None:
        MODULE.validate_source_contract()

    def test_host_and_fixture_are_the_same_concrete_implementation(self) -> None:
        self.replace(MODULE.HOST, "private previewActive: boolean = false;", "private previewActive: boolean = true;")
        self.assert_rejected("byte-identical")

    def test_preedit_cannot_be_published_as_a_committed_draft(self) -> None:
        self.replace_both_hosts("if (this.previewActive) {", "if (false) {")
        self.assert_rejected("if (this.previewActive)")

    def test_commit_calls_inside_preview_branch_are_rejected(self) -> None:
        self.replace_both_hosts(
            "      event.keepEditableState();\n      return;",
            "      event.keepEditableState();\n"
            "      this.onDraftCommit(event.text);\n"
            "      this.onDraftChange(event.text);\n"
            "      this.getUIContext().getFocusController().clearFocus();\n"
            "      this.onCommit();\n      return;",
        )
        self.assert_rejected("preview/stale-session branch must not submit or clear focus")

    def test_conflict_delayed_true_cannot_reactivate_or_publish(self) -> None:
        self.replace_both_hosts(
            "      this.editingEpoch = -1;\n      this.editing = false;\n"
            "      this.previewActive = false;\n      this.completingSubmit = false;\n"
            "      this.diagnostic = 'NativeTextInputHost: the parent draft changed during preview; editing ended and the uncommitted preview was not submitted.';",
            "      this.editing = false;\n      this.previewActive = false;\n      this.completingSubmit = false;\n"
            "      this.diagnostic = 'NativeTextInputHost: the parent draft changed during preview; editing ended and the uncommitted preview was not submitted.';",
        )
        # The required regression sequence is conflict -> delayed onEditChange(true)
        # -> rejected onChange/Done. Without generation invalidation, the old true
        # callback reopens editing and both subsequent callbacks are accepted.
        self.assert_rejected("external update during preview must invalidate")

    def test_conflict_delayed_true_scenario_is_rejected_by_current_host(self) -> None:
        host = MODULE.strip_comments((MODULE.ROOT / MODULE.HOST).read_text(encoding="utf-8"))
        conflict = MODULE.body(host, "applyExternalDraft(")
        self.assertIn("this.editingEpoch = -1;", conflict)
        lifecycle = MODULE.body(host, "private nativeEditingChanged(")
        guard_open, guard_close = MODULE.block_span(lifecycle, "if (!this.mounted || epoch !== this.editingEpoch)")
        self.assertIn("return;", lifecycle[guard_open:guard_close])
        self.assertLess(guard_close, lifecycle.index("this.editing = isEditing;"))
        for method in ("private nativeEditChanged(", "private finishNativeSubmit("):
            self.assertIn("!this.mounted || !this.editing", MODULE.body(host, method))
        focus = MODULE.body(host, "requestNativeFocus(")
        self.assertIn("this.editingEpoch = requestEpoch;", focus)
        self.assertLess(focus.index("this.editingEpoch = requestEpoch;"),
                        focus.index("getFocusController().requestFocus(this.focusId)"))
        self.assertIn("if (!isEditing)", lifecycle)
        self.assertIn("this.editingEpoch = -1;", lifecycle)

    def test_delayed_editing_true_cannot_bypass_epoch_guard(self) -> None:
        self.replace_both_hosts(
            "    if (!this.mounted || epoch !== this.editingEpoch) {\n"
            "      this.diagnostic = 'NativeTextInputHost: ignored a native editing callback from an invalidated session.';\n"
            "      return;\n    }",
            "    if (!this.mounted) {\n"
            "      this.diagnostic = 'NativeTextInputHost: ignored a native editing callback from an invalidated session.';\n"
            "      return;\n    }",
        )
        self.assert_rejected("every editing callback must reject an invalidated generation")

    def test_stale_callback_session_guard_is_required(self) -> None:
        self.replace_both_hosts("!this.mounted || !this.editing", "false")
        self.assert_rejected("stale edits require a mounted native editing-session guard")

    def test_editing_loss_must_invalidate_cached_preview(self) -> None:
        self.replace_both_hosts(
            "    this.editing = isEditing;\n    this.previewActive = false;",
            "    this.editing = isEditing;",
        )
        self.assert_rejected("editing-state transitions must invalidate cached preview")

    def test_disappearance_must_invalidate_delayed_callbacks(self) -> None:
        self.replace_both_hosts("this.invalidateNativeSession(", "// removed invalidation\n")
        self.assert_rejected("disappearance must invalidate")

    def test_parent_edit_during_preview_cannot_be_dropped(self) -> None:
        self.replace_both_hosts(
            "    }\n    this.editorDraft = this.draft;\n    if (this.previewActive) {",
            "    }\n    if (this.previewActive) {",
        )
        self.assert_rejected("every mounted external parent draft must be retained")

    def test_parent_edit_during_preview_must_end_old_session(self) -> None:
        self.replace_both_hosts(
            "      this.editingEpoch = -1;\n      this.editing = false;\n      this.previewActive = false;\n      this.completingSubmit = false;\n"
            "      this.diagnostic = 'NativeTextInputHost: the parent draft changed during preview; editing ended and the uncommitted preview was not submitted.';",
            "      this.diagnostic = 'NativeTextInputHost: the parent draft changed during preview; editing ended and the uncommitted preview was not submitted.';",
        )
        self.assert_rejected("external update during preview must invalidate")

    def test_unique_focus_identity_is_required(self) -> None:
        self.replace_both_hosts(
            "    const uniqueId: number = this.getUniqueId();\n"
            "    this.focusId = uniqueId >= 0 ? `refract_native_text_input_${uniqueId}` : '';",
            "    this.focusId = 'refract_native_text_input';",
        )
        self.assert_rejected("native identity must be read from the mounted component lifecycle")

    def test_focus_other_control_must_transfer_focus(self) -> None:
        self.replace(MODULE.PARENT, "this.getUIContext().getFocusController().requestFocus('native_other_focus');", "")
        self.assert_rejected("must actually transfer native focus")

    def test_two_real_instances_and_focus_assertions_are_required(self) -> None:
        self.replace(MODULE.PARENT, "        ComposerScreen({", "        // no second instance\n")
        self.assert_rejected("two real generated instances")

    def test_focus_scaffold_requires_native_focus_assertions(self) -> None:
        self.replace(MODULE.NATIVE_TEST, "await found[0].getId() !== await found[1].getId()", "true")
        self.assert_rejected("compared across two mounted hosts")

    def test_external_draft_cannot_overwrite_preedit(self) -> None:
        self.replace_both_hosts(
            "      this.editingEpoch = -1;\n      this.editing = false;\n      this.previewActive = false;\n      this.completingSubmit = false;\n"
            "      this.diagnostic = 'NativeTextInputHost: the parent draft changed during preview;",
            "      this.diagnostic = 'NativeTextInputHost: the parent draft changed during preview;",
        )
        self.assert_rejected("external update during preview must invalidate")

    def test_stale_binding_cannot_be_submitted(self) -> None:
        for relative in (MODULE.HOST, MODULE.CANONICAL_HOST):
            self.replace(relative, "this.onDraftCommit(committed);", "this.onDraftCommit(this.draft);")
        self.assert_rejected("onDraftCommit(committed)")

    def test_done_order_is_required(self) -> None:
        self.replace_both_hosts(
            "    this.completingSubmit = true;\n    this.controller.stopEditing();",
            "    this.completingSubmit = true;\n    this.onCommit();\n    this.controller.stopEditing();",
        )
        self.assert_rejected("main-control-flow statements differ")

    def test_preview_cannot_be_cleared_or_translated(self) -> None:
        for relative in (MODULE.HOST, MODULE.CANONICAL_HOST):
            self.replace(relative, "event.keepEditableState();", "this.controller.clearPreviewText();")
        self.assert_rejected("synthesize editing")

    def test_generated_host_cannot_be_replaced_by_an_ordinary_input(self) -> None:
        self.replace(MODULE.GENERATED, "NativeTextInputHost({", "TextInput({")
        self.assert_rejected("canonical generated output")

    def test_focus_and_recreation_checks_are_mandatory(self) -> None:
        self.replace(MODULE.NATIVE_TEST, "native_restore_composer", "native_other_focus")
        self.assert_rejected("recreation/draft-retention")

    def test_missing_host_is_explicit(self) -> None:
        (self.root / MODULE.HOST).unlink()
        self.assert_rejected("missing host sources")

    def test_check_is_explicit_about_not_compiling_or_running(self) -> None:
        result = subprocess.run(
            [sys.executable, "-I", str(SCRIPT)], cwd=MODULE.ROOT,
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no ArkTS compilation or IME execution was performed", result.stdout)


if __name__ == "__main__":
    unittest.main()
