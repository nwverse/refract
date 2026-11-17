#!/usr/bin/env python3
"""Check an authorized local HarmonyOS CLI before running its native build.

This never downloads tools, accepts vendor terms, changes configuration, installs
packages, or reads credentials. Set COMMANDLINE_TOOL_DIR to a developer-provided
parent containing command-line-tools. A PATH containing genuine vendor tools is
also accepted. Placeholders named in usage text must be replaced with local paths.

Exit status 0 means the prerequisites were found and, unless --check-only was
selected, the selected build exited zero. Neither result implies rendering,
device tests, signing, performance verification, or a validated SDK.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import os
import shutil
import subprocess
import sys
from typing import Mapping, Sequence

ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / "examples/harmony"
USAGE = """Set COMMANDLINE_TOOL_DIR to the directory containing command-line-tools.
The developer must obtain Huawei's official Command Line Tools and matching
HarmonyOS SDK, review the vendor terms, and verify the downloaded archive.
This script does not acquire tools, create an account, or accept terms.
"""


def executable(path: Path) -> bool:
    return path.is_file() and os.access(path, os.X_OK)


def resolve_tools(environ: Mapping[str, str]) -> dict[str, Path]:
    """Resolve existing vendor binaries only; do not search arbitrary repositories."""
    paths = environ.get("PATH", os.defpath).split(os.pathsep)
    configured = environ.get("COMMANDLINE_TOOL_DIR")
    if configured:
        tools = Path(configured).expanduser() / "command-line-tools"
        paths = [str(tools / "bin"), str(tools / "tool/node/bin"), *paths]
    resolved: dict[str, Path] = {}
    for name in ("devecocli", "ohpm", "java"):
        candidate = shutil.which(name, path=os.pathsep.join(paths))
        if candidate:
            path = Path(candidate)
            if executable(path):
                resolved[name] = path
    return resolved


def build_command(arguments: Sequence[str], tools: Mapping[str, Path]) -> list[str]:
    return [str(tools["devecocli"]), "build", *arguments]


def preflight(environ: Mapping[str, str]) -> tuple[dict[str, Path], list[str]]:
    tools = resolve_tools(environ)
    errors: list[str] = []
    if not environ.get("COMMANDLINE_TOOL_DIR"):
        errors.append(
            "COMMANDLINE_TOOL_DIR is unset; provide a developer-authorized extraction "
            "containing command-line-tools, or install the matching tools on PATH."
        )
    for name in ("devecocli", "ohpm"):
        if name not in tools:
            errors.append(f"required vendor executable not found: {name}")
    if "devecocli" not in tools:
        errors.append(
            "BLOCKED: no local DevEco CLI was found. The generated ArkTS is not "
            "compiled and no HAP or device result is claimed."
        )
    java = Path(environ["JAVA_HOME"]) / "bin/java" if environ.get("JAVA_HOME") else tools.get("java")
    if java is None:
        errors.append(
            "JDK is missing; the current example selects Command Line Tools 26.0.0, "
            "whose documented prerequisite is JDK 21."
        )
    elif not executable(java):
        errors.append("JAVA_HOME/bin/java is not an executable file")
    return tools, errors


def parse_arguments(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, epilog=USAGE)
    parser.add_argument("--check-only", action="store_true", help="check tools without building")
    parser.add_argument("--native-test-target", action="store_true", help="select entry@ohosTest instead of the app")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None, environ: Mapping[str, str] | None = None) -> int:
    args = parse_arguments(sys.argv[1:] if argv is None else argv)
    environment = os.environ if environ is None else environ
    tools, errors = preflight(environment)
    for error in errors:
        print(f"harmony-preflight: {error}", file=sys.stderr)
    if errors:
        print(USAGE, file=sys.stderr)
        print("harmony-preflight: BLOCKED; no native compilation was run", file=sys.stderr)
        return 2
    if args.check_only:
        print("harmony-preflight: local executables found; this is not an SDK or compiler validation")
        return 0
    target = ["--modules", "entry@ohosTest"] if args.native_test_target else []
    command = build_command(target, tools)
    result = subprocess.run(command, cwd=EXAMPLE, env=dict(environment), check=False)
    if result.returncode:
        print("harmony-preflight: vendor build FAILED; see the unmodified compiler output above", file=sys.stderr)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
