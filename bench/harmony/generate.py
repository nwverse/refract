#!/usr/bin/env python3
"""Regenerate the benchmark ArkTS, or check the committed output without writing."""

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parent.parent
    cli = root / ".build/debug/refract"
    expected = here / "entry/src/main/ets/generated/SettingsScreen.ets"
    if not cli.is_file() or not expected.is_file():
        raise SystemExit("Build the real CLI first; do not copy or hand-edit generated ArkTS.")
    with tempfile.TemporaryDirectory(prefix="refract-bench-harmony-") as temporary:
        output = Path(temporary)
        subprocess.run([
            str(cli), "generate", "--input", str(root / "bench/android/SettingsScreen.swift"),
            "--mapping", str(here / "refract.json"), "--harmony-out", str(output),
        ], cwd=root, check=True)
        actual = output / "SettingsScreen.ets"
        if not actual.is_file():
            raise SystemExit("The CLI did not produce the expected ArkTS output.")
        if args.check:
            if actual.read_bytes() != expected.read_bytes():
                raise SystemExit("Committed benchmark ArkTS differs from real CLI output.")
            print("Benchmark ArkTS matches the canonical Swift source and mapping; native compilation was not run.")
        else:
            shutil.copyfile(actual, expected)
            print("Review the regenerated ArkTS diff; this is not an ArkTS compiler result.")


if __name__ == "__main__":
    main()
