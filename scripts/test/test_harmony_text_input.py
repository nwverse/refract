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
        for relative in (MODULE.HOST, MODULE.CANONICAL_HOST):
            self.replace(relative, "if (this.previewActive) {", "if (false) {")
        self.assert_rejected("if (this.previewActive)")

    def test_external_draft_cannot_overwrite_preedit(self) -> None:
        for relative in (MODULE.HOST, MODULE.CANONICAL_HOST):
            self.replace(relative, "if (!this.previewActive) {", "if (true) {")
        self.assert_rejected("external drafts must not replace")

    def test_stale_binding_cannot_be_submitted(self) -> None:
        for relative in (MODULE.HOST, MODULE.CANONICAL_HOST):
            self.replace(relative, "this.onDraftCommit(committed);", "this.onDraftCommit(this.draft);")
        self.assert_rejected("onDraftCommit(committed)")

    def test_done_order_is_required(self) -> None:
        for relative in (MODULE.HOST, MODULE.CANONICAL_HOST):
            self.replace(relative, "this.controller.stopEditing();", "this.onCommit();\n    this.controller.stopEditing();")
        self.assert_rejected("out of order")

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
