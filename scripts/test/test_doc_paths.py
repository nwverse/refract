#!/usr/bin/env python3
"""Check maintained documentation and local links. No third-party packages required."""
from __future__ import annotations

import argparse
import re
import sys
import tempfile
import unittest
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[2]
FENCE = re.compile(r"^[ \t]*(```|~~~)")
LINK = re.compile(r"\[[^]\n]*\]\(\s*([^) \t]+)(?:[ \t]+[^)]*)?\)")
INLINE_CODE = re.compile(r"`([^`\n]+)`")
REPOSITORY_PATH = re.compile(
    r"(?<![/\w.<-])((?:\.github|docs|scripts|Sources|Tests|Fixtures|examples|bench)/"
    r"(?:[\w.+@-]+/)*[\w.+@-]+/?|(?:Package\.swift|Package\.resolved|CLAUDE\.md|AGENTS\.md))"
)
PLACEHOLDERS = re.compile(r"<[^{}<>]+>|\$\{[^{}]+\}")


def markdown_files(root: Path) -> list[Path]:
    return sorted(root.joinpath("docs").rglob("*.md"))


def without_fenced_code(text: str) -> list[tuple[int, str]]:
    """Return source lines outside examples, preserving their one-based numbers."""
    kept: list[tuple[int, str]] = []
    fence: str | None = None
    for number, line in enumerate(text.splitlines(), 1):
        match = FENCE.match(line)
        if fence is not None:
            if match and match.group(1).startswith(fence):
                fence = None
            continue
        if match:
            fence = match.group(1)
            continue
        kept.append((number, re.sub(r"<!--.*?-->", "", line)))
    return kept


def docs_index_section(index: Path) -> str:
    """Only this section defines which documentation is maintained."""
    text = index.read_text(encoding="utf-8")
    marker = "## Docs index"
    if marker not in text:
        raise ValueError("CLAUDE.md has no Docs index section")
    section = text.split(marker, 1)[1]
    return section.split("\n## ", 1)[0]


def check_index(root: Path) -> list[str]:
    index = root / "CLAUDE.md"
    if not index.is_file():
        return ["CLAUDE.md: missing documentation index"]
    index_text = docs_index_section(index)
    errors = []
    for path in markdown_files(root):
        relative = path.relative_to(root).as_posix()
        # A directory entry covers everything its own index enumerates.
        covered = f"`{relative}`" in index_text or any(
            relative.startswith(directory)
            for directory in re.findall(r"`([\w.+@-]+(?:/[\w.+@-]+)+/)`", index_text)
        )
        if not covered:
            errors.append(f"CLAUDE.md: Docs index does not list {relative}")
    return errors


def link_destination(destination: str) -> str | None:
    """Resolve a Markdown destination, or return None for an external/anchor link."""
    if destination.startswith("<") and destination.endswith(">"):
        destination = destination[1:-1]
    if destination.startswith("#") or re.match(r"^[A-Za-z][A-Za-z\d+.-]*:", destination):
        return None
    return unquote(destination.split("#", 1)[0].split("?", 1)[0])


def check_links(root: Path) -> list[str]:
    errors: list[str] = []
    documents = markdown_files(root)
    for name in ("CLAUDE.md", "AGENTS.md", "CONTRIBUTING.md", "README.md", "README.zh-CN.md"):
        candidate = root / name
        if candidate.is_file():
            documents.append(candidate)
    for document in documents:
        for number, line in without_fenced_code(document.read_text(encoding="utf-8")):
            for match in LINK.finditer(line):
                destination = link_destination(match.group(1))
                if destination is None:
                    continue
                if not destination:
                    errors.append(f"{document.relative_to(root)}:{number}: empty local link")
                    continue
                target = (document.parent / destination).resolve()
                try:
                    target.relative_to(root.resolve())
                except ValueError:
                    errors.append(f"{document.relative_to(root)}:{number}: link leaves repository: {destination}")
                    continue
                if not target.exists():
                    errors.append(f"{document.relative_to(root)}:{number}: missing link target: {destination}")
    return errors


def check_inline_paths(root: Path) -> list[str]:
    """Check literal repository-root paths in prose, not command arguments or placeholders."""
    errors: list[str] = []
    for document in markdown_files(root):
        for number, line in without_fenced_code(document.read_text(encoding="utf-8")):
            for code in INLINE_CODE.findall(line):
                for match in REPOSITORY_PATH.finditer(code):
                    path = match.group(1)
                    if PLACEHOLDERS.search(path):
                        continue
                    if not (root / path).exists():
                        errors.append(f"{document.relative_to(root)}:{number}: missing repository path: {path}")
    return errors


def check(root: Path) -> list[str]:
    return check_index(root) + check_links(root) + check_inline_paths(root)


class DocPathTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary = tempfile.TemporaryDirectory()
        self.root = Path(self._temporary.name)
        (self.root / "docs").mkdir()
        (self.root / "CLAUDE.md").write_text("## Docs index\n\n`docs/guide.md`\n", encoding="utf-8")
        (self.root / "docs/guide.md").write_text("[Index](../CLAUDE.md)\n", encoding="utf-8")

    def tearDown(self) -> None:
        self._temporary.cleanup()

    def write(self, relative: str, text: str = "") -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_empty_repository_documentation_passes(self) -> None:
        self.assertEqual(check(self.root), [])

    def test_every_maintained_doc_must_be_indexed(self) -> None:
        self.write("docs/design/topic.md")
        self.assertEqual(check_index(self.root), ["CLAUDE.md: Docs index does not list docs/design/topic.md"])

    def test_lessons_are_covered_by_their_directory_index(self) -> None:
        self.write("docs/lessons/README.md")
        self.write("docs/lessons/workflow.md")
        (self.root / "CLAUDE.md").write_text("## Docs index\n\n`docs/lessons/` and `docs/guide.md`\n", encoding="utf-8")
        self.assertEqual(check_index(self.root), [])

    def test_relative_links_and_anchor_suffixes_resolve(self) -> None:
        self.write("docs/target.md", "# Title\n")
        (self.root / "CLAUDE.md").write_text(
            "## Docs index\n\n`docs/guide.md` and `docs/target.md`\n", encoding="utf-8"
        )
        self.write("docs/guide.md", "[Section](target.md#title) and [index](../CLAUDE.md)\n")
        self.assertEqual(check_links(self.root), [])

    def test_missing_and_escaping_links_fail_with_source_locations(self) -> None:
        self.write("docs/guide.md", "[Missing](absent.md)\n[Outside](../../outside.md)\n")
        self.assertEqual(check_links(self.root), [
            "docs/guide.md:1: missing link target: absent.md",
            "docs/guide.md:2: link leaves repository: ../../outside.md",
        ])

    def test_external_links_and_examples_are_not_local_files(self) -> None:
        self.write("docs/guide.md", (
            "[Site](https://example.com/docs) [Anchor](#part)\n"
            "```sh\nrefract generate --mapping refract.json\n```\n"
        ))
        self.assertEqual(check_links(self.root), [])

    def test_local_images_must_also_exist(self) -> None:
        self.write("docs/guide.md", "![Diagram](missing.svg)\n")
        self.assertEqual(check_links(self.root), [
            "docs/guide.md:1: missing link target: missing.svg",
        ])

    def test_inline_repository_paths_are_checked(self) -> None:
        self.write("docs/guide.md", "Read `docs/missing.md` and `Package.swift`.\n")
        self.assertEqual(check_inline_paths(self.root), [
            "docs/guide.md:1: missing repository path: docs/missing.md",
            "docs/guide.md:1: missing repository path: Package.swift",
        ])

    def test_commands_arguments_and_placeholders_are_not_paths(self) -> None:
        self.write("docs/guide.md", (
            "Use `--output Fixtures/<case>/` and `--android-out <dir>`, or `Fixtures/<case>/Input.swift`.\n"
            "```text\nSources/NotReal.swift\n```\n"
        ))
        self.assertEqual(check_inline_paths(self.root), [])

    def test_unclosed_fence_does_not_hide_later_docs(self) -> None:
        self.write("docs/guide.md", "~~~\n[Missing](absent.md)\n")
        self.assertEqual(check_links(self.root), [])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="run the checker's unit tests")
    args = parser.parse_args()
    if args.self_test:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(DocPathTests)
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        return 0 if result.wasSuccessful() else 1
    errors = check(ROOT)
    for error in errors:
        print(f"doc_paths: {error}", file=sys.stderr)
    if errors:
        print(f"doc_paths: {len(errors)} error(s)", file=sys.stderr)
        return 1
    print(f"doc_paths: checked {len(markdown_files(ROOT))} maintained docs and local links")
    return 0


if __name__ == "__main__":
    sys.exit(main())
