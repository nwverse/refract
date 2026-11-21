#!/usr/bin/env python3
"""Synthetic package archival tests; these are not Instruments or performance evidence."""

import hashlib
import io
import os
import sys
import tempfile
import unittest
import zipfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

from archive_trace import ArchiveError, archive_trace, main


class ArchiveTraceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "raw"
        self.root.mkdir()
        self.source = self.root / "generated-scroll-0.trace"
        (self.source / "nested").mkdir(parents=True)
        (self.source / "trace.xml").write_bytes(b"<synthetic-trace/>\n")
        (self.source / "nested" / "samples.bin").write_bytes(bytes(range(256)))
        self.output = self.root / "generated-scroll-0.trace.zip"

    def test_nested_package_round_trip_and_manifest_metadata(self):
        size, checksum = archive_trace(self.source, self.output)
        self.assertEqual(size, self.output.stat().st_size)
        self.assertEqual(checksum, hashlib.sha256(self.output.read_bytes()).hexdigest())
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(archive.namelist(), ["generated-scroll-0.trace/nested/samples.bin",
                                                   "generated-scroll-0.trace/trace.xml"])
            self.assertEqual(archive.read("generated-scroll-0.trace/trace.xml"), b"<synthetic-trace/>\n")
            self.assertEqual(archive.read("generated-scroll-0.trace/nested/samples.bin"), bytes(range(256)))
            self.assertTrue(all(info.date_time == (1980, 1, 1, 0, 0, 0) for info in archive.infolist()))

        second = self.root / "second.trace.zip"
        archive_trace(self.source, second)
        self.assertEqual(self.output.read_bytes(), second.read_bytes())
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            self.assertEqual(main([str(self.source), "--output", str(self.root / "cli.trace.zip")]), 0)
        metadata = dict(line.split("=", 1) for line in stdout.getvalue().splitlines())
        self.assertEqual(int(metadata["bytes"]), (self.root / "cli.trace.zip").stat().st_size)
        self.assertEqual(metadata["sha256"], hashlib.sha256((self.root / "cli.trace.zip").read_bytes()).hexdigest())

    def test_missing_empty_linked_or_wrong_shaped_sources_are_rejected(self):
        for mutation in ("missing", "empty", "file", "source-link", "wrong-suffix"):
            with self.subTest(mutation=mutation):
                source = self.root / f"{mutation}.trace"
                if mutation == "empty":
                    source.mkdir()
                elif mutation == "file":
                    source.write_bytes(b"not a package")
                elif mutation == "source-link":
                    source.symlink_to(self.source, target_is_directory=True)
                elif mutation == "wrong-suffix":
                    source = self.root / "ordinary"
                    source.mkdir()
                    (source / "member").write_bytes(b"synthetic")
                with self.assertRaises(ArchiveError):
                    archive_trace(source, self.root / f"{mutation}.trace.zip")
                self.assertFalse((self.root / f"{mutation}.trace.zip").exists())

    def test_member_symlink_fifo_and_special_file_are_not_followed_or_archived(self):
        for mutation in ("file-link", "directory-link", "fifo"):
            with self.subTest(mutation=mutation):
                source = self.root / f"{mutation}.trace"
                source.mkdir()
                if mutation == "file-link":
                    (source / "link").symlink_to(self.source / "trace.xml")
                elif mutation == "directory-link":
                    (source / "link").symlink_to(self.source / "nested", target_is_directory=True)
                elif os.name == "posix":
                    os.mkfifo(source / "pipe")
                else:
                    continue
                with self.assertRaisesRegex(ArchiveError, "ordinary files|links"):
                    archive_trace(source, self.root / f"{mutation}.trace.zip")
                self.assertFalse((self.root / f"{mutation}.trace.zip").exists())

    def test_existing_output_is_never_replaced_and_cli_fails_closed(self):
        self.output.write_bytes(b"existing evidence")
        with self.assertRaisesRegex(ArchiveError, "Refusing to replace"):
            archive_trace(self.source, self.output)
        self.assertEqual(self.output.read_bytes(), b"existing evidence")
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            self.assertEqual(main([str(self.source), "--output", str(self.output)]), 2)
        self.assertIn("Refusing to replace", stderr.getvalue())
        self.assertEqual(self.output.read_bytes(), b"existing evidence")

    def test_archive_cannot_be_created_inside_its_source_package(self):
        for output in (self.source / "inside.trace.zip", self.source / "nested" / "inside.trace.zip"):
            with self.subTest(output=output), self.assertRaisesRegex(ArchiveError, "contain its own"):
                archive_trace(self.source, output)
            self.assertFalse(output.exists())
        with self.assertRaisesRegex(ArchiveError, "suffix"):
            archive_trace(self.source, self.root / "not-a-trace.zip")

    def test_raw_directory_rejection_remains_compatible_with_archived_file(self):
        # This synthetic file tests the existing ordinary-file evidence boundary;
        # it does not assert that arbitrary bytes are an Instruments recording.
        from paired_report import EvidenceError, artifact

        archive_trace(self.source, self.output)
        entry = {"path": "raw/generated-scroll-0.trace.zip", "kind": "xctrace", "variant": "generated",
                 "scenario": "scroll", "iteration": 0, "bytes": self.output.stat().st_size,
                 "sha256": hashlib.sha256(self.output.read_bytes()).hexdigest()}
        result, path = artifact(dict(entry), self.root.parent, "ios")
        self.assertEqual(path, entry["path"])
        with self.assertRaisesRegex(EvidenceError, "Missing, linked or empty"):
            artifact(dict(entry, path="raw/generated-scroll-0.trace"), self.root.parent, "ios")


if __name__ == "__main__":
    unittest.main()
