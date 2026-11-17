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
        commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True,
                                capture_output=True, text=True).stdout.strip()
        notices, text = package.load_notices(commit)
        pins = json.loads(package.committed_bytes(commit, "Package.resolved").decode())["pins"]
        self.assertEqual(set(notices), {pin["identity"] for pin in pins})
        for pin in pins:
            self.assertEqual(notices[pin["identity"]]["revision"], pin["state"]["revision"])
            self.assertIn(pin["state"]["revision"].encode(), text)
        document = json.loads(package.committed_bytes(commit, "scripts/release/third_party_notices.json"))
        license_path = next(iter(document.values()))["licenseFile"]
        original = package.committed_bytes
        with mock.patch.object(package, "committed_bytes", side_effect=lambda revision, path: (
            b"changed license" if path == license_path else original(revision, path))):
            with self.assertRaisesRegex(ValueError, "digest"):
                package.load_notices(commit)

    def test_selected_revision_ignores_dirty_provenance_files(self) -> None:
        original_root = package.ROOT
        fixture = self.root / "repository"
        fixture.mkdir()
        self.addCleanup(lambda: setattr(package, "ROOT", original_root))
        package.ROOT = fixture
        environment = dict(os.environ)
        environment["GIT_OBJECT_DIRECTORY"] = str(fixture / ".git/objects")
        environment["GIT_ALTERNATE_OBJECT_DIRECTORIES"] = ""
        git = lambda *args: subprocess.run(["git", *args], cwd=fixture, env=environment,
                                           check=True, capture_output=True, text=True).stdout
        subprocess.run(["git", "init", "-q"], cwd=fixture, env=environment, check=True)
        lockfile = {"pins": [{"identity": "swift-syntax", "state": {"revision": "first-revision"}}]}
        notice = {"swift-syntax": {"url": "https://example.com/source", "version": "1", "revision": "first-revision",
                                   "license": "Apache-2.0", "licenseFile": "vendor/LICENSE.txt", "sha256": ""}}
        notice["swift-syntax"]["sha256"] = hashlib.sha256(b"first committed license").hexdigest()
        for path, data in (("Package.resolved", json.dumps(lockfile).encode()),
                           ("scripts/release/third_party_notices.json", json.dumps(notice).encode()),
                           ("vendor/LICENSE.txt", b"first committed license"),
                           ("LICENSE", b"first project license"),
                           ("Package.swift", b"first manifest"),
                           ("Sources/RefractMapping/Resources/refract.schema.json", b"first schema"),
                           ("Sources/RefractCLI/Version.swift", b'static let sourceRevision = "unstamped"\n')):
            destination = fixture / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
        subprocess.run(["git", "add", "Package.resolved", "Package.swift", "scripts/release/third_party_notices.json",
                        "vendor/LICENSE.txt", "LICENSE", "Sources/RefractMapping/Resources/refract.schema.json",
                        "Sources/RefractCLI/Version.swift"], cwd=fixture, env=environment, check=True)
        subprocess.run(["git", "-c", "user.name=Example", "-c", "user.email=me@example.com",
                        "commit", "-qm", "first provenance fixture"], cwd=fixture, env=environment, check=True)
        first = git("rev-parse", "HEAD").strip()
        lockfile["pins"][0]["state"]["revision"] = "second-revision"
        notice["swift-syntax"]["version"] = "2"
        notice["swift-syntax"]["revision"] = "second-revision"
        notice["swift-syntax"]["sha256"] = hashlib.sha256(b"second committed license").hexdigest()
        for path, data in (("Package.resolved", json.dumps(lockfile).encode()),
                           ("scripts/release/third_party_notices.json", json.dumps(notice).encode()),
                           ("vendor/LICENSE.txt", b"second committed license"),
                           ("LICENSE", b"second project license"),
                           ("Package.swift", b"second manifest"),
                           ("Sources/RefractMapping/Resources/refract.schema.json", b"second schema")):
            (fixture / path).write_bytes(data)
        subprocess.run(["git", "add", "Package.resolved", "Package.swift", "scripts/release/third_party_notices.json",
                        "vendor/LICENSE.txt", "LICENSE", "Sources/RefractMapping/Resources/refract.schema.json"],
                       cwd=fixture, env=environment, check=True)
        subprocess.run(["git", "-c", "user.name=Example", "-c", "user.email=me@example.com",
                        "commit", "-qm", "second provenance fixture"], cwd=fixture, env=environment, check=True)
        second = git("rev-parse", "HEAD").strip()
        self.assertNotEqual(first, second)
        self.assertEqual(package.committed_bytes(first, "LICENSE"), b"first project license")
        self.assertEqual(package.committed_bytes(second, "LICENSE"), b"second project license")
        for path, data in (("Package.resolved", b"dirty lockfile"),
                           ("scripts/release/third_party_notices.json", b"dirty notices"),
                           ("vendor/LICENSE.txt", b"dirty third-party license"),
                           ("LICENSE", b"dirty project license"),
                           ("Package.swift", b"dirty manifest")):
            (fixture / path).write_bytes(data)
        notices, text = package.load_notices(first)
        self.assertIn(b"first committed license", text)
        self.assertIn(b"first-revision", text)
        self.assertNotIn(b"second", text)
        self.assertNotIn(b"dirty", text)
        products = fixture / "products"
        schema = products / "refract_RefractMapping.bundle/refract.schema.json"
        schema.parent.mkdir(parents=True)
        schema.write_bytes(package.committed_bytes(first, "Sources/RefractMapping/Resources/refract.schema.json"))
        (products / "refract").write_bytes(b"executable")
        entries = {name: data for name, _, data in package.binary_entries(products, first, {}, text)}
        for archive_path, source_path in (("LICENSE", "LICENSE"),
                                          ("source/Package.resolved", "Package.resolved"),
                                          ("source/Package.swift", "Package.swift")):
            self.assertEqual(entries[archive_path], package.committed_bytes(first, source_path))
            self.assertNotEqual(entries[archive_path], package.committed_bytes(second, source_path))
        self.assertEqual(entries["THIRD-PARTY-NOTICES.txt"], text)

        # Discard the deliberate caller edits before creating incomplete revisions.
        git("reset", "-q", "--hard", second)

        # Validate the entire real entry point without running a Swift build.
        output = fixture / "artifacts"
        missing_paths = ["Package.resolved", "scripts/release/third_party_notices.json", "vendor/LICENSE.txt",
                         "LICENSE", "Package.swift", "Sources/RefractMapping/Resources/refract.schema.json"]
        with mock.patch.object(package, "package_once", side_effect=AssertionError("build must not start")):
            for missing in missing_paths:
                git("rm", "-q", missing)
                git("-c", "user.name=Example", "-c", "user.email=me@example.com",
                    "commit", "-qm", f"missing {missing}")
                with self.assertRaisesRegex(ValueError, "lacks required packaging input.*select a complete revision"):
                    package.create_package(git("rev-parse", "HEAD").strip(), output, False)
                git("reset", "-q", "--hard", second)
        self.assertFalse(output.exists())

    def test_required_provenance_must_be_a_regular_blob(self) -> None:
        commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
                                capture_output=True, check=True).stdout.strip()
        with mock.patch.object(package.subprocess, "run", return_value=subprocess.CompletedProcess(
                [], 0, stdout="tree\n", stderr="")):
            with self.assertRaisesRegex(ValueError, "LICENSE.*regular file"):
                package.committed_bytes(commit, "LICENSE")

    def test_provenance_rejects_mismatched_selected_revision_and_unsafe_paths(self) -> None:
        commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True,
                                capture_output=True, text=True).stdout.strip()
        with mock.patch.object(package, "committed_json", side_effect=lambda revision, path: (
            {"pins": [{"identity": "swift-syntax", "state": {"revision": "different-revision"}}]}
            if path == "Package.resolved" else {"swift-syntax": {"revision": "selected-revision"}})):
            with self.assertRaisesRegex(ValueError, "missing or stale"):
                package.load_notices(commit)
        with self.assertRaisesRegex(ValueError, "normalized"):
            package.committed_bytes(commit, "../LICENSE")

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
