#!/usr/bin/env python3
"""Compile, install and verify the generated ArkUI screen on an owned target.

This script never obtains a toolchain, accepts terms, configures signing, creates
an emulator or selects an implicit device. The developer must authorize and
prepare the official tools, SDK, signing and target first. See
examples/harmony/verification/README.md for the exact command contract.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Mapping, Sequence

# Python -I removes the script directory; load the sibling by its explicit path.
PREFLIGHT_SPEC = importlib.util.spec_from_file_location(
    "refract_harmony_preflight", Path(__file__).resolve().with_name("check_harmony_toolchain.py")
)
assert PREFLIGHT_SPEC is not None and PREFLIGHT_SPEC.loader is not None
PREFLIGHT = importlib.util.module_from_spec(PREFLIGHT_SPEC)
PREFLIGHT_SPEC.loader.exec_module(PREFLIGHT)

ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / "examples/harmony"
CAPTURES = (
    "generated-settings-light.png",
    "generated-settings-light-layout.json",
    "generated-settings-light-after-scroll.png",
    "generated-settings-light-after-scroll-layout.json",
    "generated-settings-light-after-scroll-return.png",
    "generated-settings-light-after-scroll-return-layout.json",
    "generated-settings-dark.png",
    "generated-settings-dark-layout.json",
)
EXPECTED_CASES = (
    ("GeneratedSettingsRender", "native_controls_binding_model_list_and_captures"),
    ("GeneratedSettingsRender", "native_dark_theme_and_accessibility_layout"),
)
SUMMARY = re.compile(r"(?m)^OHOS_REPORT_RESULT: stream=Tests run: (\d+), Failure: (\d+), Error: (\d+), Pass: (\d+), Ignore: (\d+)$")
CASE_RESULT = re.compile(r"(?m)^OHOS_REPORT_STATUS: (class|test)=(.*)$")
CASE_STATUS = re.compile(r"(?m)^OHOS_REPORT_STATUS_CODE: (-?\d+)$")
SUITE_START = re.compile(r"(?m)^OHOS_REPORT_SUM: (\d+)$")
SUITE_DONE = re.compile(r"(?m)^OHOS_REPORT_STATUS: suiteconsuming=(\d+)$")
TASK_DONE = re.compile(r"(?m)^OHOS_REPORT_STATUS: taskconsuming=(\d+)$")
TERMINAL = re.compile(r"(?m)^OHOS_REPORT_CODE: (-?\d+)$")
ARGUMENT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/@+-]*$")


class VerificationError(RuntimeError):
    """An incomplete execution cannot become a render-success report."""


def execute(command: Sequence[str], log_path: Path, *, cwd: Path = ROOT,
            environment: Mapping[str, str] | None = None, timeout: int = 600) -> subprocess.CompletedProcess[str]:
    with log_path.open("a", encoding="utf-8") as log:
        log.write(json.dumps({"command": list(command), "cwd": str(cwd)}) + "\n")
        log.flush()
        try:
            sys.stdout.write(f"harmony-render: running {command[0]}; see {log_path}\n")
            result = subprocess.run(
                list(command), cwd=cwd, env=dict(environment) if environment is not None else None,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False, timeout=timeout,
            )
        except subprocess.TimeoutExpired as error:
            raise VerificationError(f"command timed out after {timeout}s: {command[0]}") from error
        log.write(result.stdout)
        log.write(f"\nexit_status={result.returncode}\n")
    if result.returncode:
        raise VerificationError(f"command failed with exit {result.returncode}; inspect {log_path}")
    return result


def validate_result(output: str) -> dict[str, object]:
    """Parse pinned suite/case/task lifecycles and require one successful terminal result."""
    results = SUMMARY.findall(output)
    terminals = TERMINAL.findall(output)
    if len(results) != 1 or terminals != ["0"]:
        raise VerificationError("missing, ambiguous or failed native summary/terminal result")
    tests, failures, errors, passed, ignored = (int(value) for value in results[0])
    if tests != len(EXPECTED_CASES) or failures or errors or ignored or passed != tests:
        raise VerificationError(f"native test summary did not pass completely: {results[0]}")

    lifecycle: list[tuple[str, str, int | None]] = []
    fields: list[tuple[str, str, int | None]] = []

    def flush_record() -> None:
        nonlocal fields
        if not fields:
            return
        kinds = [kind for kind, _, _ in fields]
        if "class" in kinds:
            if kinds == ["sum", "class"] or kinds == ["class", "suiteconsuming"] \
                    or (kinds[0] == "class" and kinds[-1] == "code" and kinds.count("class") == 1
                        and kinds.count("test") == 1 and kinds.count("code") == 1):
                lifecycle.extend(fields)
                fields = []
                return
            raise VerificationError("incomplete, reordered or ambiguous native report record")
        if fields[0][0] == "sum" or any(kind in ("code", "test", "suiteconsuming") for kind in kinds):
            raise VerificationError("native lifecycle record has no suite or case identity")
        # Timing and diagnostic fields from an earlier case do not form a new record.
        fields = []

    for line in output.splitlines():
        if re.fullmatch(
            r"OHOS_REPORT_STATUS: (current|id|numtests|stream|consuming|stack|skipReason|shortMsg|hookError|"
            r"currentWorkerName)=.*",
            line,
        ):
            continue
        match = re.fullmatch(r"OHOS_REPORT_STATUS: (class|test)=(.*)", line)
        if match:
            if match[1] == "class" and not (len(fields) == 1 and fields[0][0] == "sum"):
                flush_record()
            kind, value = match.groups()
            fields.append((kind, value, None))
            continue
        match = SUITE_DONE.fullmatch(line)
        if match:
            fields.append(("suiteconsuming", "", int(match[1])))
            continue
        match = TASK_DONE.fullmatch(line)
        if match:
            if fields:
                raise VerificationError("task completed before a native record was complete")
            lifecycle.append(("taskconsuming", "", int(match[1])))
            continue
        match = SUITE_START.fullmatch(line)
        if match:
            if fields:
                flush_record()
            fields.append(("sum", match[1], int(match[1])))
            continue
        match = CASE_STATUS.fullmatch(line)
        if match:
            fields.append(("code", match[1], int(match[1])))
            continue
        if SUMMARY.fullmatch(line):
            flush_record()
            lifecycle.append(("summary", "", None))
            continue
        if TERMINAL.fullmatch(line):
            if fields:
                raise VerificationError("terminal result interrupted a native report record")
            lifecycle.append(("terminal", "", None))
            continue
        if fields:
            raise VerificationError("malformed or ambiguous native report record")
    flush_record()

    suites = {suite for suite, _ in EXPECTED_CASES}
    suite_starts: list[str] = []
    suite_ends: list[str] = []
    case_records: list[tuple[str, str, int]] = []
    index = 0
    while index < len(lifecycle):
        kind, value, duration = lifecycle[index]
        if kind == "sum":
            if duration != len(EXPECTED_CASES) or index + 1 >= len(lifecycle):
                raise VerificationError("invalid suite start record")
            next_kind, next_value, _ = lifecycle[index + 1]
            if next_kind != "class" or next_value not in suites:
                raise VerificationError("suite start has no selected suite name")
            suite_starts.append(next_value)
            index += 2
        elif kind == "class":
            if index + 1 >= len(lifecycle) or value not in suites:
                raise VerificationError("class-only or unknown native report record")
            next_kind, next_value, next_duration = lifecycle[index + 1]
            if next_kind == "suiteconsuming":
                suite_ends.append(value)
                index += 2
            elif next_kind == "test":
                if index + 2 >= len(lifecycle):
                    raise VerificationError("incomplete native case record")
                code_kind, code_value, code = lifecycle[index + 2]
                if code_kind != "code":
                    raise VerificationError("native case has no status code")
                case_records.append((value, next_value, int(code)))
                index += 3
            else:
                raise VerificationError("class record is neither a suite end nor a case")
        elif kind == "summary":
            if len(suite_starts) != 1 or len(suite_ends) != 1 or index != len(lifecycle) - 3:
                raise VerificationError("summary arrived before the selected suite completed or after task completion")
            index += 1
        elif kind == "terminal":
            if index != len(lifecycle) - 2 or len(suite_starts) != 1 or len(suite_ends) != 1 \
                    or lifecycle[index - 1][0] != "summary" or lifecycle[index + 1][0] != "taskconsuming":
                raise VerificationError("terminal/task records are not the final ordered lifecycle records")
            index += 2
        else:
            raise VerificationError("unexpected or ambiguous native lifecycle record")
    if len(suite_starts) != 1 or len(suite_ends) != 1 or suite_starts != suite_ends:
        raise VerificationError("selected suite start/end records are incomplete or ambiguous")

    observed: list[tuple[str, str]] = []
    pending: tuple[str, str] | None = None
    for suite, name, code in case_records:
        case = (suite, name)
        if case not in EXPECTED_CASES or code not in (0, 1):
            raise VerificationError(f"unexpected or failed native case result: {suite}#{name}={code}")
        if code == 1:
            if pending is not None:
                raise VerificationError(f"native case has no success result: {pending[0]}#{pending[1]}")
            pending = case
        elif pending != case or case in observed:
            raise VerificationError(f"native case has an incomplete or duplicate success: {suite}#{name}")
        else:
            observed.append(case)
            pending = None
    if pending is not None or observed != list(EXPECTED_CASES):
        raise VerificationError("not every required native rendering case completed successfully")
    return {
        "tests": tests, "failures": failures, "errors": errors, "passed": passed, "ignored": ignored,
        "cases": [f"{suite}#{name}" for suite, name in EXPECTED_CASES],
    }


def source_revision() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True,
    )
    revision = result.stdout.strip()
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise VerificationError("source revision is unavailable")
    dirty = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, check=True, capture_output=True, text=True)
    if dirty.stdout:
        raise VerificationError("the source checkout has uncommitted changes; evidence must identify a committed revision")
    return revision


def tool_version(tools: Mapping[str, Path], log_path: Path) -> str:
    result = execute([str(tools["devecocli"]), "--version"], log_path, cwd=EXAMPLE)
    version = result.stdout.strip()
    if not version:
        raise VerificationError("the vendor CLI returned no version")
    return version


def parse_arguments(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True, help="explicitly allocated target serial")
    parser.add_argument("--target-class", choices=("emulator", "device"), required=True)
    parser.add_argument("--target-description", required=True, help="target OS/build/model supplied by its owner")
    parser.add_argument("--app-hap", required=True)
    parser.add_argument("--test-hap", required=True)
    parser.add_argument("--output", required=True, help="new private evidence directory")
    parser.add_argument("--skip-build", action="store_true", help="only for an already compiled exact source revision")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_arguments(list(sys.argv[1:] if argv is None else argv))
    if not ARGUMENT.fullmatch(args.target):
        print("target must be a serial without whitespace or shell metacharacters", file=sys.stderr)
        return 2
    args.output = Path(args.output)
    args.app_hap = Path(args.app_hap)
    args.test_hap = Path(args.test_hap)
    if args.output.exists():
        print("verification output must be a new directory; refusing to mix evidence", file=sys.stderr)
        return 2
    args.output.mkdir(parents=True)
    log_path = args.output / "commands.log"
    metadata: dict[str, object] = {
        "status": "incomplete", "renderVerified": False, "performanceMeasured": False,
        "targetClass": args.target_class, "targetDescription": args.target_description,
        "startedUtc": datetime.now(timezone.utc).isoformat(),
    }
    try:
        metadata["sourceRevision"] = source_revision()
        metadata["appHapSha256"] = hashlib.sha256(args.app_hap.read_bytes()).hexdigest()
        metadata["testHapSha256"] = hashlib.sha256(args.test_hap.read_bytes()).hexdigest()
        tools, errors = PREFLIGHT.preflight(os.environ)
        if errors:
            raise VerificationError("; ".join(errors))
        if not shutil.which("hdc"):
            raise VerificationError("authorized hdc executable was not found on PATH")
        metadata["toolchainVersion"] = tool_version(tools, log_path)
        if not args.skip_build:
            for command in (["build"], ["build", "--modules", "entry@ohosTest"]):
                execute([str(tools["devecocli"]), *command], log_path, cwd=EXAMPLE, environment=os.environ)
        hdc = ["hdc", "-t", args.target]
        execute([*hdc, "install", str(args.app_hap.resolve())], log_path)
        execute([*hdc, "install", str(args.test_hap.resolve())], log_path)
        all_output = ""
        command = [*hdc, "shell", "aa", "test", "-b", "com.example.refract", "-m", "entry_test",
                   "-s", "unittest", "OpenHarmonyTestRunner", "-s", "class", "GeneratedSettingsRender",
                   "-s", "timeout", "60000"]
        all_output += execute(command, log_path, timeout=180).stdout
        for name in CAPTURES:
            destination = args.output / name
            execute([*hdc, "file", "recv", f"/data/storage/el2/base/cache/{name}", str(destination)], log_path)
            if not destination.is_file() or destination.stat().st_size == 0:
                raise VerificationError(f"missing capture artifact: {name}")
            if name.endswith(".png"):
                if not destination.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"):
                    raise VerificationError(f"capture is not PNG: {name}")
            else:
                json.loads(destination.read_text(encoding="utf-8"))
        metadata["nativeTests"] = validate_result(all_output)
        metadata["status"] = "executed-awaiting-human-capture-inspection"
        metadata["captures"] = list(CAPTURES)
        return 0
    except (OSError, ValueError, VerificationError, json.JSONDecodeError) as error:
        metadata["status"] = "failed-or-blocked"
        metadata["blocker"] = str(error)
        print(f"harmony-render: {error}", file=sys.stderr)
        return 1
    finally:
        metadata["finishedUtc"] = datetime.now(timezone.utc).isoformat()
        (args.output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        print("NO RENDERED EVIDENCE IS COMPLETE UNTIL A HUMAN INSPECTS BOTH THEMES AND THE LAYOUT DUMPS")


if __name__ == "__main__":
    sys.exit(main())
