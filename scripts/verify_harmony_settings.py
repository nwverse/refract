#!/usr/bin/env python3
"""Compile, install and verify the generated ArkUI screen on an owned target.

This script never obtains a toolchain, accepts terms, configures signing, creates
an emulator or selects an implicit device. The developer must authorize and
prepare the official tools, SDK, signing and target first. See
examples/harmony/verification/README.md for the exact command contract.
"""
from __future__ import annotations

import argparse
import contextlib
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
import tempfile
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
PACKAGE_OUTPUTS = {
    "app": EXAMPLE / "entry/build/default/outputs/default/entry-default-signed.hap",
    "test": EXAMPLE / "entry/build/default/outputs/default/entry-ohosTest-signed.hap",
}


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


def format_observed_cases(cases: Sequence[tuple[str, str]]) -> list[str]:
    """Serialize the successful case identities observed in the native output."""
    return [f"{suite}#{name}" for suite, name in cases]


def validate_result(output: str, expected_cases: Sequence[tuple[str, str]] = EXPECTED_CASES) -> dict[str, object]:
    """Parse pinned suite/case/task lifecycles and require one successful terminal result."""
    results = SUMMARY.findall(output)
    terminals = TERMINAL.findall(output)
    if len(results) != 1 or terminals != ["0"]:
        raise VerificationError("missing, ambiguous or failed native summary/terminal result")
    tests, failures, errors, passed, ignored = (int(value) for value in results[0])
    if tests != len(expected_cases) or failures or errors or ignored or passed != tests:
        raise VerificationError(f"native test summary did not pass completely: {results[0]}")

    lifecycle: list[tuple[str, str, int | None]] = []
    fields: list[tuple[str, str, int | None]] = []

    def flush_record() -> None:
        nonlocal fields
        if not fields:
            return
        kinds = [kind for kind, _, _ in fields]
        if "class" in kinds:
            if kinds == ["sum", "class"] or kinds == ["class", "suiteconsuming"]:
                lifecycle.extend(fields)
                fields = []
                return
            if kinds[:6] != ["class", "current", "id", "numtests", "stream", "test"] \
                    or kinds[-1] != "code" or kinds.count("class") != 1 \
                    or kinds.count("test") != 1 or kinds.count("code") != 1:
                raise VerificationError("incomplete, reordered or ambiguous native report record")
            # Validate documented case metadata, then retain the downstream
            # class/test/code shape unchanged.
            lifecycle.extend([fields[index] for index in (0, 5, len(fields) - 1)])
            fields = []
            return
        if fields[0][0] == "sum" or any(kind in ("code", "test", "suiteconsuming") for kind in kinds):
            raise VerificationError("native lifecycle record has no suite or case identity")
        # Timing and diagnostic fields from an earlier case do not form a new record.
        fields = []

    for line in output.splitlines():
        match = re.fullmatch(
            r"OHOS_REPORT_STATUS: (consuming|stack|skipReason|shortMsg|hookError|currentWorkerName)=.*",
            line,
        )
        if match:
            continue
        match = re.fullmatch(r"OHOS_REPORT_STATUS: (current|id|numtests|stream)=(.*)", line)
        if match:
            fields.append((match[1], match[2], None))
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

    suites = {suite for suite, _ in expected_cases}
    suite_starts: list[str] = []
    suite_ends: list[str] = []
    case_records: list[tuple[str, str, int]] = []
    index = 0
    while index < len(lifecycle):
        kind, value, duration = lifecycle[index]
        if kind == "sum":
            if duration != len(expected_cases) or index + 1 >= len(lifecycle):
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
        if case not in expected_cases or code not in (0, 1):
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
    if pending is not None or observed != list(expected_cases):
        raise VerificationError("not every required selected native case completed successfully")
    return {
        "tests": tests, "failures": failures, "errors": errors, "passed": passed, "ignored": ignored,
        "cases": format_observed_cases(observed),
    }


def selected_suite(parameters: Sequence[tuple[str, str]]) -> str:
    """Reject repeated, missing, conflicting or unknown native suite selectors."""
    selectors = [(key, value) for key, value in parameters if key in ("class", "refractSuite")]
    values = dict(selectors)
    if len(selectors) != 2 or set(values) != {"class", "refractSuite"} \
            or values["class"] != values["refractSuite"] \
            or values["class"] not in {"GeneratedSettingsRender", "GeneratedComposer"}:
        raise VerificationError("duplicate, missing, conflicting or unknown native suite parameters")
    return values["class"]


def selected_suite_command(hdc: Sequence[str], suite: str) -> list[str]:
    """Allow only the registered test suites and exactly one matching selector."""
    selected = selected_suite((("class", suite), ("refractSuite", suite)))
    return [
        *hdc, "shell", "aa", "test", "-b", "com.example.refract", "-m", "entry_test",
        "-s", "unittest", "OpenHarmonyTestRunner", "-s", "class", selected,
        "-s", "refractSuite", selected, "-s", "timeout", "60000",
    ]


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


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def regular_file(path: Path, description: str) -> Path:
    """Resolve an artifact only after rejecting links and non-regular files."""
    if path.is_symlink() or not path.is_file():
        if not path.exists() and not path.is_symlink():
            raise FileNotFoundError(path)
        raise VerificationError(f"{description} is not a regular file; refusing installation")
    resolved = path.resolve(strict=True)
    if not resolved.is_file():
        raise VerificationError(f"{description} is not a regular file; refusing installation")
    return resolved


def native_packages(tools: Mapping[str, Path], log_path: Path,
                    snapshot_root: Path | None = None) -> dict[str, object]:
    """Build with old canonical files quarantined, retaining restorable copies."""
    if snapshot_root is None:
        with package_snapshots() as snapshots:
            return native_packages(tools, log_path, snapshots["app"].parent)
    snapshot_root.mkdir(mode=0o700, exist_ok=True)
    if snapshot_root.is_symlink() or not snapshot_root.is_dir() \
            or snapshot_root.stat().st_mode & 0o777 != 0o700:
        raise VerificationError("package snapshot path is not a private directory")
    for command in (["build"], ["build", "--modules", "entry@ohosTest"]):
        execute([str(tools["devecocli"]), *command], log_path, cwd=EXAMPLE, environment=os.environ)
    built: dict[str, Path] = {}
    for role, path in PACKAGE_OUTPUTS.items():
        source = regular_file(path, f"newly built canonical {role} HAP")
        destination = snapshot_root / f"snapshot-{role}.hap"
        with source.open("rb") as source_file, destination.open("xb") as destination_file:
            shutil.copyfileobj(source_file, destination_file)
        built[role] = destination
    return package_provenance(PACKAGE_OUTPUTS, built)


@contextlib.contextmanager
def package_snapshots() -> object:
    """Own snapshot lifetime and never delete a pre-existing canonical HAP."""
    with tempfile.TemporaryDirectory(prefix="refract-harmony-install-snapshots.") as temporary:
        root = Path(temporary)
        build = root / "build"
        build.mkdir(mode=0o700)
        saved: dict[str, tuple[Path, Path]] = {}
        failed = True
        try:
            for role, path in PACKAGE_OUTPUTS.items():
                if path.is_symlink() or (path.exists() and not path.is_file()):
                    raise VerificationError(f"canonical {role} HAP path is not a regular file")
                if path.exists():
                    destination = build / f"previous-{role}.hap"
                    path.rename(destination)
                    saved[role] = (path, destination)
            try:
                yield {role: build / f"snapshot-{role}.hap" for role in PACKAGE_OUTPUTS}
                failed = False
            except BaseException:
                # A partial output from a failed build is not the verified
                # package. Retain it separately and restore the old canonical.
                for role, path in PACKAGE_OUTPUTS.items():
                    if role in saved and not path.is_symlink() and path.is_file():
                        path.replace(build / f"snapshot-{role}.hap")
                    elif role in saved and path.is_symlink():
                        path.unlink()
                raise
        finally:
            conflict = False

            def preserve() -> Path:
                preserved = Path(tempfile.mkdtemp(prefix="refract-harmony-preserved-packages."))
                preserved.rmdir()
                try:
                    root.rename(preserved)
                except OSError:
                    preserved.rmdir()
                    raise
                return preserved

            try:
                for role, (path, destination) in saved.items():
                    if path.exists() or path.is_symlink():
                        conflict = True
                    else:
                        path.parent.mkdir(parents=True, exist_ok=True)
                        destination.rename(path)
                if conflict:
                    preserved = preserve()
                    print(f"harmony-render: previous canonical HAPs preserved at {preserved}", file=sys.stderr)
                elif failed:
                    preserved = preserve()
                    print(f"harmony-render: failed-run package snapshots preserved at {preserved}", file=sys.stderr)
            except OSError:
                # TemporaryDirectory cleanup must not delete unrecovered packages.
                preserved = preserve()
                print(f"harmony-render: unrecovered canonical HAPs preserved at {preserved}", file=sys.stderr)
                raise


def package_provenance(selected: Mapping[str, Path], built: Mapping[str, Path]) -> dict[str, object]:
    """Recheck selected bytes immediately before each installation."""
    if set(selected) != {"app", "test"} or set(built) != {"app", "test"}:
        raise VerificationError("app and test HAP build-output identities are both required")
    artifacts: dict[str, object] = {}
    for role in ("app", "test"):
        selected_path = regular_file(selected[role], f"selected {role} HAP")
        built_path = regular_file(built[role], f"snapshot of this run's {role} HAP")
        selected_hash = sha256(selected_path)
        built_hash = sha256(built_path)
        if selected_hash != built_hash:
            raise VerificationError(
                f"selected {role} HAP differs from the native build output snapshot; refusing installation"
            )
        artifacts[role] = {
            "buildOutputPath": str(PACKAGE_OUTPUTS[role].resolve()),
            "buildOutputSha256": built_hash,
            "selectedPath": str(selected_path),
            "selectedSha256": selected_hash,
            "installSnapshotPath": str(built_path),
            "matchesBuildOutput": True,
        }
    return {"sourceBinding": "byte-identical-to-current-build-snapshots", "artifacts": artifacts}


def parse_arguments(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True, help="explicitly allocated target serial")
    parser.add_argument("--target-class", choices=("emulator", "device"), required=True)
    parser.add_argument("--target-description", required=True, help="target OS/build/model supplied by its owner")
    parser.add_argument("--app-hap", type=Path,
                        help="app HAP path; must match the canonical output of this run's native build")
    parser.add_argument("--test-hap", type=Path,
                        help="test HAP path; must match the canonical output of this run's native build")
    parser.add_argument("--output", required=True, help="new private evidence directory")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_arguments(list(sys.argv[1:] if argv is None else argv))
    if not ARGUMENT.fullmatch(args.target):
        print("target must be a serial without whitespace or shell metacharacters", file=sys.stderr)
        return 2
    args.output = Path(args.output)
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
        tools, errors = PREFLIGHT.preflight(os.environ)
        if errors:
            raise VerificationError("; ".join(errors))
        if not shutil.which("hdc"):
            raise VerificationError("authorized hdc executable was not found on PATH")
        metadata["toolchainVersion"] = tool_version(tools, log_path)
        with package_snapshots() as snapshot_paths:
            metadata["nativePackages"] = native_packages(tools, log_path, snapshot_paths["app"].parent)
            selected = {
                role: args.app_hap if role == "app" and args.app_hap is not None else built
                for role, built in PACKAGE_OUTPUTS.items()
            }
            if args.test_hap is not None:
                selected["test"] = args.test_hap
            hdc = ["hdc", "-t", args.target]
            for role in selected:
                # Reject replacement before every install; then open only the
                # immutable run snapshot, never the mutable selected path again.
                metadata["nativePackages"] = package_provenance(selected, snapshot_paths)
                install = package_provenance(selected, snapshot_paths)["artifacts"][role]["installSnapshotPath"]
                execute([*hdc, "install", str(install)], log_path)
            command = selected_suite_command(hdc, "GeneratedSettingsRender")
            all_output = execute(command, log_path, timeout=180).stdout
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
