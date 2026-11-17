#!/usr/bin/env python3
"""Offline tests for the packaging policy, archive layout and clean-source build."""
from __future__ import annotations

import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("refract_package_cli", ROOT / "scripts/package_cli.py")
assert SPEC and SPEC.loader
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)


class PackagingUnitTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="refract-package-test.")
        self.root = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_archive_is_byte_identical_with_canonical_metadata(self) -> None:
        entries = [("bin/refract", 0o755, b"executable"), ("LICENSE", 0o644, b"license")]
        first = package.deterministic_tar("refract-test", entries)
        second = package.deterministic_tar("refract-test", list(reversed(entries)))
        self.assertEqual(first, second)
        with tarfile.open(fileobj=io.BytesIO(first)) as archive:
            self.assertTrue(all(member.mtime == 0 and member.uid == 0 and member.gid == 0
                                and not member.uname and not member.gname for member in archive))
            self.assertEqual(archive.getnames(), ["refract-test", "refract-test/bin", "refract-test/LICENSE",
                                                  "refract-test/bin/refract"])

    def test_stamp_changes_revision_without_touching_version(self) -> None:
        source = b'enum RefractVersion {\n    static let current = "0.1.0"\n    static let sourceRevision = "old"\n}\n'
        stamped = package.version_source(source, "a" * 40)
        self.assertIn(b'static let current = "0.1.0"', stamped)
        self.assertIn(b'"' + b"a" * 40 + b'"', stamped)
        self.assertNotIn(b"old", stamped)
        with self.assertRaisesRegex(ValueError, "exactly one"):
            package.version_source(b"missing declaration", "a" * 40)

    def test_revision_must_be_an_unambiguous_commit(self) -> None:
        with self.assertRaisesRegex(ValueError, "full"):
            package.validate_revision("main")
        with mock.patch.object(package, "run", return_value="tree"):
            with self.assertRaisesRegex(ValueError, "not a commit"):
                package.validate_revision("a" * 40)

    def test_notices_cover_lockfile_and_detect_tampering(self) -> None:
        notices, text = package.load_notices()
        pins = json.loads((ROOT / "Package.resolved").read_text(encoding="utf-8"))["pins"]
        self.assertEqual(set(notices), {pin["identity"] for pin in pins})
        for pin in pins:
            self.assertEqual(notices[pin["identity"]]["revision"], pin["state"]["revision"])
            self.assertIn(pin["state"]["revision"].encode(), text)
        with mock.patch.object(package, "ROOT", self.root):
            with self.assertRaises(FileNotFoundError):
                package.load_notices()

    def test_clean_source_archive_contains_only_committed_inputs_and_stamped_version(self) -> None:
        commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
                                capture_output=True, check=True).stdout.strip()
        output = self.root / "source.tar.gz"
        package.source_archive(commit, output)
        with tarfile.open(output) as archive:
            names = archive.getnames()
            root = f"refract-source-{package.VERSION}"
            self.assertIn(f"{root}/Package.resolved", names)
            self.assertIn(f"{root}/scripts/release/third_party_notices.json", names)
            self.assertNotIn(f"{root}/.build", names)
            self.assertNotIn(f"{root}/.worktrees", names)
            version = archive.extractfile(f"{root}/Sources/RefractCLI/Version.swift")
            assert version
            self.assertIn(commit.encode(), version.read())
            self.assertTrue(all(member.mtime == 0 and member.uid == 0 and member.gid == 0 for member in archive))


class PackagingEndToEndTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("REFRACT_PACKAGE_E2E") == "1", "opt in to two real clean Swift builds")
    def test_real_archive_from_two_clean_checkouts(self) -> None:
        with tempfile.TemporaryDirectory(prefix="refract-package-e2e.") as temporary:
            output = Path(temporary) / "artifacts"
            completed = subprocess.run([sys.executable, str(ROOT / "scripts/package_cli.py"),
                                        "--output", str(output), "--verify-reproducible"],
                                       cwd=ROOT, text=True, capture_output=True, timeout=1800)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            archives = list(output.glob("refract-*-*.tar.gz"))
            self.assertEqual(len(archives), 2, completed.stdout)
            for archive in archives:
                self.assertTrue(archive.with_suffix(archive.suffix + ".sha256").is_file())
            self.assertIn("byte-identical", completed.stdout)


if __name__ == "__main__":
    unittest.main()
