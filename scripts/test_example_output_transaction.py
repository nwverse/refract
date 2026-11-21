#!/usr/bin/env python3
"""Exercise the real CLI example-output transaction used by the Android CI gate."""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Sequence

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/ci.yml"
STEP_NAME = "Check committed native outputs without writing"


def workflow_check_command(root: Path = ROOT) -> list[str]:
    """Use the actual CI step, not a second hand-maintained output/input list."""
    workflow = (root / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    match = re.search(
        rf"      - name: {re.escape(STEP_NAME)}\n        run: \|\n(?P<step>(?:          .*\n)+)",
        workflow,
    )
    if match is None:
        raise ValueError(f"missing CI step: {STEP_NAME}")
    step = match.group("step")
    command: list[str] = []
    for line in step.splitlines():
        token = line.strip().removesuffix("\\").strip()
        if not token:
            continue
        if token == ".build/debug/refract check":
            command.extend((str(root / ".build/debug/refract"), "check"))
            continue
        if token == ".build/debug/refract":
            token = str(root / ".build/debug/refract")
        else:
            option, separator, value = token.partition(" ")
            if option in ("--input", "--mapping", "--android-out", "--harmony-out") and separator and value.startswith("examples/"):
                command.extend((option, str(root / value)))
                continue
            if token in ("check", "--input", "--mapping", "--android-out", "--harmony-out"):
                pass
            elif token.startswith("examples/"):
                token = str(root / token)
            else:
                raise ValueError(f"unexpected CI output-transaction token: {token}")
        command.append(token)
    if command[1:2] != ["check"]:
        raise ValueError("the CI native-output step must invoke refract check")
    return command


def run(command: Sequence[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, capture_output=True, text=True, check=False)


def check(root: Path = ROOT) -> subprocess.CompletedProcess[str]:
    return run(workflow_check_command(root))


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="run the full negative and positive CLI regression")
    arguments = parser.parse_args(argv)
    result = check()
    if result.returncode:
        sys.stderr.write(result.stderr)
        return result.returncode
    print("Exact CI example-output transaction passed over both committed native roots")
    if not arguments.self_test:
        return 0

    with tempfile.TemporaryDirectory(prefix="refract-example-transaction-test.") as temporary:
        temporary_root = Path(temporary)
        missing_input = temporary_root / "missing-input"
        shutil.copytree(ROOT, missing_input, ignore=shutil.ignore_patterns(".git", ".build", ".worktrees"))
        (missing_input / ".build").mkdir()
        (missing_input / ".build/debug").symlink_to(ROOT / ".build/debug", target_is_directory=True)
        workflow = missing_input / ".github/workflows/ci.yml"
        workflow.write_text(
            workflow.read_text(encoding="utf-8").replace(
                "            --input examples/shared/InteropTextInputHost.swift \\\n", "", 1,
            ),
            encoding="utf-8",
        )
        rejected = check(missing_input)
        if rejected.returncode == 0 or "unexpected generated output" not in rejected.stderr:
            print("Missing text-input input was not rejected as an unexpected generated host", file=sys.stderr)
            return 1

        for relative in (
            "examples/android/app/refract/generated/screens/InteropTextInputHost.kt",
            "examples/harmony/entry/src/main/ets/generated/InteropTextInputHost.ets",
        ):
            missing_output = temporary_root / f"missing-{Path(relative).suffix.removeprefix('.')}"
            shutil.copytree(ROOT, missing_output, ignore=shutil.ignore_patterns(".git", ".build", ".worktrees"))
            (missing_output / ".build").mkdir()
            (missing_output / ".build/debug").symlink_to(ROOT / ".build/debug", target_is_directory=True)
            (missing_output / relative).unlink()
            rejected = check(missing_output)
            if rejected.returncode == 0 or "missing committed output" not in rejected.stderr:
                print(f"Missing generated host was not rejected: {relative}", file=sys.stderr)
                return 1
    print("CLI regression rejects a missing input and either missing generated host; freshness remains enforced")
    return 0


if __name__ == "__main__":
    sys.exit(main())
