#!/usr/bin/env python3
"""Quarantine diagnostic artifacts from failed macro instrumentation.

This never creates the complete-evidence manifest consumed by report.py. The
result is explicitly incomplete and failed, including when AndroidX produced no
JSON, a missing/empty trace, or a first-frame deadline failure.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path, PurePosixPath


class PreservationError(RuntimeError):
    pass


def load_json(path: Path) -> dict[str, object]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise PreservationError(f"Cannot read run metadata {path.name}: {error}") from error
    if not isinstance(payload, dict):
        raise PreservationError(f"Run metadata must be a JSON object: {path.name}")
    return payload


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def preserve(input_directory: Path, output: Path, environment: Path,
             instrumentation_status: Path, instrumentation_log: Path, exit_code: int) -> dict[str, object]:
    if not 1 <= exit_code <= 255:
        raise PreservationError("Failed evidence requires a nonzero instrumentation exit code")
    if (output / "failed-evidence-manifest.json").exists() or (output / "evidence-manifest.json").exists():
        raise PreservationError("Refusing to mix failure diagnostics with an existing evidence manifest")
    metadata = load_json(environment)
    revision = metadata.get("source_revision")
    if metadata.get("status") != "ready" or metadata.get("emulator") is not True or \
            not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise PreservationError("A verified emulator probe with a full source revision is required")
    status = load_json(instrumentation_status)
    if status.get("status") != "failed" or status.get("exit_code") != exit_code:
        raise PreservationError("Instrumentation status does not match the failed Gradle invocation")
    if not input_directory.is_dir() or not instrumentation_log.is_file():
        raise PreservationError("The current run's AndroidX output directory and instrumentation log are required")

    output.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".failed-evidence-staging-", dir=output))
    published = False
    artifacts: list[dict[str, object]] = []

    def retain(source: Path, relative: PurePosixPath, kind: str) -> None:
        if relative.is_absolute() or ".." in relative.parts or relative.parts[0] != "raw":
            raise PreservationError("A diagnostic artifact escapes its raw directory")
        if not source.is_file() or source.is_symlink():
            raise PreservationError(f"Diagnostic artifact is not a regular file: {source.name}")
        before = digest(source)
        destination = staging / Path(*relative.parts)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            raise PreservationError(f"Duplicate diagnostic artifact: {relative}")
        shutil.copyfile(source, destination)
        # A deadline may leave a writer active. Never publish a file whose bytes
        # changed during this best-effort snapshot as a coherent raw artifact.
        if digest(source) != before or digest(destination) != before:
            raise PreservationError(f"Diagnostic artifact changed during preservation: {relative}")
        artifacts.append({"path": relative.as_posix(), "kind": kind,
                          "bytes": destination.stat().st_size, "sha256": before})

    try:
        retain(environment, PurePosixPath("raw/environment.json"), "environment")
        retain(instrumentation_status, PurePosixPath("raw/instrumentation-status.json"), "instrumentation_status")
        retain(instrumentation_log, PurePosixPath("raw/instrumentation.log"), "instrumentation_log")
        for source in sorted(input_directory.rglob("*")):
            if source.is_symlink() or not source.is_file():
                continue
            if source.name.endswith("benchmarkData.json"):
                kind = "androidx_json"
            elif source.name.endswith(".perfetto-trace"):
                kind = "perfetto_trace"
            else:
                continue
            relative = PurePosixPath("raw/additional-output", *source.relative_to(input_directory).parts)
            retain(source, relative, kind)
        manifest = {
            "schema": 1,
            "kind": "failed-android-macro-evidence",
            "status": "failed",
            "complete": False,
            "diagnostic_only": True,
            "device_result": False,
            "environment_label": "emulator",
            "source_revision": revision,
            "instrumentation": {"exit_code": exit_code, "deadline_exceeded": exit_code == 124},
            "reason": "Instrumentation failed; retained JSON and traces are incomplete and cannot support a performance result.",
            "artifacts": artifacts,
            "limitations": [
                "No generated/reference pairing, sample completeness or no-regression result was established.",
                "Perfetto files are unvalidated snapshots and may be absent, empty or incomplete.",
                "Emulator diagnostics are not physical-device evidence.",
            ],
        }
        (staging / "failed-evidence-manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        raw_output = output / "raw"
        if raw_output.exists() and any(raw_output.iterdir()):
            raise PreservationError("Refusing to publish over existing raw evidence")
        (staging / "raw").rename(raw_output)
        (staging / "failed-evidence-manifest.json").rename(output / "failed-evidence-manifest.json")
        published = True
        return manifest
    finally:
        # An interrupted or rejected snapshot remains in its unique staging
        # directory and has no published manifest that could be mistaken for a result.
        if published:
            staging.rmdir()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-directory", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--environment", required=True, type=Path)
    parser.add_argument("--instrumentation-status", required=True, type=Path)
    parser.add_argument("--instrumentation-log", required=True, type=Path)
    parser.add_argument("--instrumentation-exit-code", required=True, type=int)
    args = parser.parse_args(argv)
    try:
        manifest = preserve(args.input_directory, args.output, args.environment,
                            args.instrumentation_status, args.instrumentation_log,
                            args.instrumentation_exit_code)
    except (PreservationError, OSError) as error:
        print(f"failed-evidence-preservation: ERROR: {error}", file=sys.stderr)
        return 2
    print(f"Quarantined {len(manifest['artifacts'])} failed-run artifacts; no macro pass is claimed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
