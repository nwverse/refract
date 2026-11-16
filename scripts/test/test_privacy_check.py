#!/usr/bin/env python3
"""Isolated integration tests for scripts/privacy_check.py."""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "privacy_check.py"
PRIVATE = "fixture-sensitive-value"
BANNED = "aster" + "-gate"


class PrivacyCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary = tempfile.TemporaryDirectory()
        sandbox = Path(self._temporary.name)
        self.root = sandbox / "repository"
        self.home = sandbox / "home"
        self.config = sandbox / "config"
        self.hooks = sandbox / "empty-hooks"
        for directory in (self.root / "scripts", self.home, self.config, self.hooks):
            directory.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SOURCE, self.root / "scripts/privacy_check.py")
        (self.config / "private-words.txt").write_text(
            f"{PRIVATE} # fixture rule\nshort\nrunner\n", encoding="utf-8"
        )
        self.env = os.environ.copy()
        self.env.update({
            "HOME": str(self.home),
            "REFRACT_CONFIG_DIR": str(self.config),
            "LOGNAME": "fixture-user",
            "USER": "fixture-user",
            "LNAME": "fixture-user",
            "USERNAME": "fixture-user",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "PYTHONDONTWRITEBYTECODE": "1",
        })
        self.git("init", "--quiet", "--initial-branch=main")
        self.write("README.md", "A public fixture. Contact me@example.com.\n")
        self.git("add", "--", "README.md", "scripts/privacy_check.py")
        self.git("commit", "--quiet", "-m", "Initial public fixture")
        self.base = self.git("rev-parse", "HEAD").stdout.strip()

    def tearDown(self) -> None:
        self._temporary.cleanup()

    def git(self, *args: str, message: str | None = None) -> subprocess.CompletedProcess[str]:
        command = ["git", "-C", str(self.root), "-c", f"core.hooksPath={self.hooks}",
                   "-c", "user.name=Fixture User", "-c", "user.email=me@example.com",
                   "-c", "commit.gpgSign=false", *args]
        environment = self.env.copy()
        if message is not None:
            command[command.index("-m") + 1] = message
        return subprocess.run(command, env=environment, text=True, capture_output=True, check=True)

    def write(self, relative: str, text: str | bytes) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(text, bytes):
            path.write_bytes(text)
        else:
            path.write_text(text, encoding="utf-8")
        return path

    def scan(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-I", str(self.root / "scripts/privacy_check.py"), *args],
            env=self.env, text=True, capture_output=True, check=False,
        )

    def assert_rejected(self, result: subprocess.CompletedProcess[str], kind: str) -> None:
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(kind, result.stderr)
        self.assertNotIn(PRIVATE, result.stderr)
        self.assertNotIn(BANNED, result.stderr)

    def test_clean_tracked_repository_passes(self) -> None:
        self.assertEqual(self.scan().returncode, 0, self.scan().stderr)

    def test_untracked_files_are_not_part_of_tracked_mode(self) -> None:
        self.write("untracked.txt", PRIVATE)
        self.assertEqual(self.scan().returncode, 0, self.scan().stderr)

    def test_tracked_content_reports_kind_and_line_without_value(self) -> None:
        self.write("README.md", "public\n" + PRIVATE + "\n")
        result = self.scan()
        self.assert_rejected(result, "private word")
        self.assertIn("README.md:2", result.stderr)
        self.assertIn("private-words.txt", result.stderr)

    def test_tracked_path_is_checked(self) -> None:
        self.write(PRIVATE + ".txt", "public")
        self.git("add", "--", PRIVATE + ".txt")
        result = self.scan()
        self.assert_rejected(result, "path <redacted>.txt:1")
        self.assertIn("<redacted>", result.stderr)

    def test_content_hit_in_a_private_path_is_also_redacted(self) -> None:
        self.write(PRIVATE + ".txt", "also " + PRIVATE)
        self.git("add", "--", PRIVATE + ".txt")
        result = self.scan()
        self.assert_rejected(result, "<redacted>.txt:1")
        self.assertNotIn(PRIVATE, result.stdout)

    def test_banned_name_is_checked_without_spelling_it_in_tests(self) -> None:
        self.write("README.md", BANNED)
        self.git("add", "--", "README.md")
        self.assert_rejected(self.scan(), "banned name")

    def test_non_public_email_and_each_private_network_are_checked(self) -> None:
        # Construct synthetic samples at run time: they are test inputs, not private values to commit literally.
        non_public_email = "@".join(("person", "example.invalid-example"))
        private_addresses = [
            ".".join(map(str, octets))
            for octets in ((10, 1, 2, 3), (172, 16, 2, 3), (172, 31, 2, 3), (192, 168, 2, 3), (100, 64, 2, 3))
        ]
        for sample, kind in [(non_public_email, "email address")] + [
            (address, "private IPv4 address") for address in private_addresses
        ]:
            with self.subTest(sample=sample):
                self.write("README.md", sample)
                self.git("add", "--", "README.md")
                self.assert_rejected(self.scan(), kind)

    def test_public_addresses_documentation_domains_and_version_numbers_pass(self) -> None:
        self.write("README.md", (
            "me@example.com other@sub.example.org nobody@users.noreply.github.com\n"
            "docs@example.test invalid@example.invalid local@example.localhost\n"
            "8.8.8.8 172.15.0.1 172.32.0.1 100.128.0.1 1.2.3.999 1.2.3.4.5\n"
        ))
        self.git("add", "--", "README.md")
        self.assertEqual(self.scan().returncode, 0, self.scan().stderr)

    def test_short_private_word_requires_a_token_boundary(self) -> None:
        self.write("README.md", "The word short is blocked; shorter and shortish are not.\n")
        self.git("add", "--", "README.md")
        self.assert_rejected(self.scan(), "private word")
        self.write("README.md", "shorter shortish\n")
        self.git("add", "--", "README.md")
        self.assertEqual(self.scan().returncode, 0, self.scan().stderr)

    def test_local_notes_supply_code_spans_but_not_existing_repo_paths(self) -> None:
        self.write("CLAUDE.local.md", "Use `fixture-local-note` and `README.md`.\n")
        self.write("README.md", "fixture-local-note\n")
        self.git("add", "--", "README.md")
        self.assert_rejected(self.scan(), "CLAUDE.local.md")
        self.write("README.md", "README.md\n")
        self.git("add", "--", "README.md")
        self.assertEqual(self.scan().returncode, 0, self.scan().stderr)

    def test_home_directory_and_login_are_redacted(self) -> None:
        for sample in (str(self.home), "fixture-user"):
            with self.subTest(rule="machine value"):
                self.write("README.md", sample)
                self.git("add", "--", "README.md")
                result = self.scan()
                self.assert_rejected(result, "private word")
                self.assertNotIn(sample, result.stderr)

    def test_binary_content_is_ignored_but_its_path_is_checked(self) -> None:
        self.write("binary.dat", b"\0" + PRIVATE.encode())
        self.git("add", "--", "binary.dat")
        self.assertEqual(self.scan().returncode, 0, self.scan().stderr)
        self.write(PRIVATE + ".dat", b"\0public")
        self.git("add", "--", PRIVATE + ".dat")
        self.assert_rejected(self.scan(), "private word")

    def test_symlink_does_not_read_its_external_target(self) -> None:
        outside = self.write("outside.txt", PRIVATE)
        os.symlink(outside, self.root / "linked.txt")
        self.git("add", "--", "linked.txt")
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_staged_mode_reads_the_index_not_unstaged_edits(self) -> None:
        self.write("README.md", PRIVATE)
        self.assertEqual(self.scan("--staged").returncode, 0, self.scan("--staged").stderr)
        self.assert_rejected(self.scan(), "private word")
        self.git("add", "--", "README.md")
        self.assert_rejected(self.scan("--staged"), "private word")

    def test_staged_deletions_are_not_scanned(self) -> None:
        self.write("obsolete.txt", PRIVATE)
        self.git("add", "--", "obsolete.txt")
        self.git("commit", "--quiet", "-m", "Temporary fixture")
        (self.root / "obsolete.txt").unlink()
        self.git("add", "--", "obsolete.txt")
        self.assertEqual(self.scan("--staged").returncode, 0, self.scan("--staged").stderr)

    def test_commit_message_checks_only_what_git_records(self) -> None:
        message = self.write("message.txt", (
            "# " + PRIVATE + " in a comment\n"
            "Public subject\n"
            "# ------------------------ >8 ------------------------\n"
            + PRIVATE + " below scissors\n"
        ))
        self.assertEqual(self.scan("--commit-msg", str(message)).returncode, 0)
        message.write_text("Public subject\n\n" + PRIVATE, encoding="utf-8")
        result = self.scan("--commit-msg", str(message))
        self.assert_rejected(result, "message:3")

    def test_message_mode_checks_the_entire_squash_message(self) -> None:
        message = self.write("message.txt", "# not a comment in this mode\n" + PRIVATE)
        self.assert_rejected(self.scan("--message", str(message)), "message:2")

    def test_range_checks_changed_files_and_commit_messages(self) -> None:
        self.write("README.md", PRIVATE)
        self.git("add", "--", "README.md")
        secret_message = "Subject containing " + PRIVATE
        self.git("commit", "--quiet", "-m", "placeholder", message=secret_message)
        head = self.git("rev-parse", "HEAD").stdout.strip()
        result = self.scan("--range", f"{self.base}..{head}")
        self.assert_rejected(result, "commit messages")
        self.assertIn("README.md", result.stderr)

    def test_clean_range_passes(self) -> None:
        self.write("docs/guide.md", "Public documentation\n")
        self.git("add", "--", "docs/guide.md")
        self.git("commit", "--quiet", "-m", "Add public documentation")
        head = self.git("rev-parse", "HEAD").stdout.strip()
        self.assertEqual(self.scan("--range", f"{self.base}..{head}").returncode, 0)

    def test_unrelated_range_scans_the_entire_head_and_its_history(self) -> None:
        tree = self.git("write-tree").stdout.strip()
        orphan_message = "Orphan with " + PRIVATE
        orphan = self.git("commit-tree", tree, "-m", "placeholder", message=orphan_message).stdout.strip()
        self.write("README.md", PRIVATE)
        self.git("add", "--", "README.md")
        tree = self.git("write-tree").stdout.strip()
        orphan = self.git("commit-tree", tree, "-p", orphan, "-m", "Add a private fixture").stdout.strip()
        result = self.scan("--range", f"{self.base}..{orphan}")
        self.assert_rejected(result, "commit messages")
        self.assertIn("README.md", result.stderr)

    def test_scanner_source_itself_can_contain_the_rules(self) -> None:
        self.assertEqual(self.scan("--range", f"{self.base}..{self.base}").returncode, 0)

    def test_invalid_arguments_print_usage_and_return_two(self) -> None:
        for arguments in (
            ("--not-a-mode",), ("--range", "not-a-range"), ("--range", self.base),
            ("--commit-msg",), ("--message",),
        ):
            with self.subTest(arguments=arguments):
                result = self.scan(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertIn("usage", result.stderr.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
