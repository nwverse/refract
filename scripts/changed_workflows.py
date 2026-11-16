#!/usr/bin/env python3
"""Select tracked workflow files that changed in a pull request or push."""
from __future__ import annotations

import argparse
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

WORKFLOWS = ".github/workflows"
EMPTY_TREE = "0000000000000000000000000000000000000000"


def changed_workflows(event: str, base: str | None, head: str | None) -> list[str]:
    if not head:
        raise ValueError("the checked-out head SHA is required")
    if event == "pull_request":
        if not base:
            raise ValueError("a pull request needs its base SHA")
        revision = f"{base}...{head}"
        changed = git_lines("diff", "--name-only", revision, "--", WORKFLOWS)
    elif event == "push" and base and base != EMPTY_TREE:
        changed = git_lines("diff", "--name-only", f"{base}..{head}", "--", WORKFLOWS)
    else:
        # A new branch/tag or manual dispatch has no meaningful previous revision.
        changed = git_lines("ls-files", WORKFLOWS)
    return [path for path in changed if Path(path).suffix in (".yml", ".yaml")]


def git_lines(*arguments: str) -> list[str]:
    result = subprocess.run(["git", *arguments], check=True, text=True, capture_output=True)
    return result.stdout.splitlines()


class ChangedWorkflowTests(unittest.TestCase):
    def test_pull_request_uses_three_dot_diff(self) -> None:
        with patch(f"{__name__}.git_lines", return_value=[".github/workflows/ci.yml", "Sources/A.swift"]) as git:
            self.assertEqual(changed_workflows("pull_request", "base-sha", "head-sha"), [".github/workflows/ci.yml"])
            git.assert_called_once_with(
                "diff", "--name-only", "base-sha...head-sha", "--", ".github/workflows"
            )

    def test_push_uses_the_before_revision(self) -> None:
        with patch(f"{__name__}.git_lines", return_value=[".github/workflows/ci.yaml"]) as git:
            self.assertEqual(changed_workflows("push", "base-sha", "head-sha"), [".github/workflows/ci.yaml"])
            git.assert_called_once_with("diff", "--name-only", "base-sha..head-sha", "--", ".github/workflows")

    def test_first_push_lints_all_tracked_workflows(self) -> None:
        with patch(f"{__name__}.git_lines", return_value=[".github/workflows/ci.yml"]) as git:
            self.assertEqual(changed_workflows("push", EMPTY_TREE, "head-sha"), [".github/workflows/ci.yml"])
            git.assert_called_once_with("ls-files", ".github/workflows")

    def test_manual_dispatch_lints_all_tracked_workflows(self) -> None:
        with patch(f"{__name__}.git_lines", return_value=[]):
            self.assertEqual(changed_workflows("workflow_dispatch", None, "head-sha"), [])

    def test_missing_context_fails_instead_of_using_a_wrong_revision(self) -> None:
        with self.assertRaises(ValueError):
            changed_workflows("pull_request", None, "head-sha")
        with self.assertRaises(ValueError):
            changed_workflows("push", None, None)

    def test_non_workflow_and_non_yaml_entries_are_excluded(self) -> None:
        with patch(f"{__name__}.git_lines", return_value=[".github/workflows/README.md", "docs/ci.md"]):
            self.assertEqual(changed_workflows("workflow_dispatch", None, "head-sha"), [])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", required=True)
    parser.add_argument("--base")
    parser.add_argument("--head", required=True)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(ChangedWorkflowTests)
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        raise SystemExit(0 if result.wasSuccessful() else 1)
    for path in changed_workflows(arguments.event, arguments.base, arguments.head):
        print(path)


if __name__ == "__main__":
    main()
