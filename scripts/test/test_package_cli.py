#!/usr/bin/env python3
"""Offline tests for the packaging policy, archive layout and clean-source build."""
from __future__ import annotations

import importlib.util
import hashlib
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

    def test_extraction_rejects_traversal_links_and_special_modes(self) -> None:
        for name, kind, mode in (("root/../escape", tarfile.REGTYPE, 0o644),
                                 ("root/link", tarfile.SYMTYPE, 0o777),
                                 ("root/file", tarfile.REGTYPE, 0o4755)):
            archive_path = self.root / f"{kind}-{mode}.tar.gz"
            with tarfile.open(archive_path, "w:gz") as archive:
                root = tarfile.TarInfo("root")
                root.type = tarfile.DIRTYPE
                archive.addfile(root)
                member = tarfile.TarInfo(name)
                member.type = kind
                member.mode = mode
                if kind == tarfile.REGTYPE:
                    member.size = 1
                    archive.addfile(member, io.BytesIO(b"x"))
                else:
                    member.linkname = "target"
                    archive.addfile(member)
            with self.assertRaises(ValueError):
                package.extract_archive(archive_path, self.root / f"installed-{kind}-{mode}")

    def test_resource_bundle_preserves_linux_and_macos_layouts(self) -> None:
        for relative in ("refract.schema.json", "Contents/Resources/refract.schema.json"):
            products = self.root / relative.split("/")[0]
            schema = products / "refract_RefractMapping.bundle" / relative
            schema.parent.mkdir(parents=True)
            schema.write_bytes(b"schema")
            self.assertEqual(package.resource_bundle(products), schema)
        duplicate = self.root / "duplicate/refract_RefractMapping.bundle"
        for relative in ("refract.schema.json", "Contents/Resources/refract.schema.json"):
            schema = duplicate / relative
            schema.parent.mkdir(parents=True, exist_ok=True)
            schema.write_bytes(b"schema")
        with self.assertRaisesRegex(ValueError, "one regular mapping schema"):
            package.resource_bundle(self.root / "duplicate")

    def test_platform_specific_link_and_strip_flags(self) -> None:
        self.assertIn("--static-swift-stdlib", package.swift_build_flags("linux"))
        self.assertNotIn("--static-swift-stdlib", package.swift_build_flags("macos"))
        for os_name, flag in (("linux", "--strip-debug"), ("macos", "-S")):
            with mock.patch.object(package, "run") as run:
                package.strip_executable(self.root / "refract", os_name)
                self.assertEqual(run.call_args.args[0], ["strip", flag, str(self.root / "refract")])

    def test_checksum_verification_is_mandatory_on_each_host(self) -> None:
        archive = self.root / "artifact.tar.gz"
        archive.write_bytes(b"archive")
        checksum = archive.with_suffix(".gz.sha256")
        checksum.write_text(f"{hashlib.sha256(b'archive').hexdigest()}  {archive.name}\n", encoding="ascii")
        for os_name, tool in (("linux", "sha256sum"), ("macos", "shasum")):
            with mock.patch.object(package, "run", return_value="OK") as run:
                package.verify_checksums(self.root, [archive], os_name)
                self.assertEqual(run.call_args.args[0][:3], [tool] + (["--check", "--strict"] if os_name == "linux" else ["-a", "256"]))
            with mock.patch.object(package.shutil, "which", return_value=None):
                with self.assertRaisesRegex(ValueError, "required"):
                    package.verify_checksums(self.root, [archive], os_name)
        checksum.write_text("0" * 64 + f"  {archive.name}\n", encoding="ascii")
        with self.assertRaisesRegex(ValueError, "mismatch"):
            package.verify_checksums(self.root, [archive], "linux")

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
        temporary = tempfile.TemporaryDirectory(prefix="refract-package-e2e.")
        self.addCleanup(temporary.cleanup)
        if os.environ.get("REFRACT_PACKAGE_OUTPUT"):
            output = Path(os.environ["REFRACT_PACKAGE_OUTPUT"]).resolve()
        else:
            output = Path(temporary.name) / "artifacts"
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
