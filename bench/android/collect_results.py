#!/usr/bin/env python3
"""Copy AndroidX JSON and Perfetto traces into an immutable per-run directory."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path


class EvidenceError(RuntimeError):
    pass


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def trace_identity(name: str) -> tuple[str | None, str | None]:
    lowered = name.lower()
    variant = "generated" if "generated" in lowered else "reference" if "reference" in lowered else None
    if "startup" in lowered:
        scenario = "startup"
    elif "stateupdate" in lowered:
        scenario = "stateUpdate"
    elif "macrobenchmark" in lowered or "scroll" in lowered:
        scenario = "scroll"
    else:
        scenario = None
    return variant, scenario


def copy_artifact(source: Path, raw: Path, index: int) -> dict[str, object]:
    destination = raw / f"{index:03d}-{source.name}"
    if destination.exists():
        raise EvidenceError(f"Refusing to overwrite an evidence file: {destination.name}")
    shutil.copyfile(source, destination)
    return {"path": f"raw/{destination.name}", "bytes": destination.stat().st_size, "sha256": digest(destination)}


def collect(input_directory: Path, output: Path) -> dict[str, object]:
    if not input_directory.is_dir():
        raise EvidenceError("AndroidX additional-output directory is absent; instrumentation did not produce evidence.")
    if (output / "evidence-manifest.json").exists() or (output / "json-files.txt").exists():
        raise EvidenceError("Refusing to replace an existing evidence manifest; choose a new run directory.")
    raw = output / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    json_sources = sorted(path for path in input_directory.rglob("*benchmarkData.json") if path.is_file())
    if not json_sources:
        raise EvidenceError("No AndroidX benchmark JSON was produced; this is not a passing run.")
    benchmark_json = [copy_artifact(path, raw, index) for index, path in enumerate(json_sources, 1)]
    trace_sources = sorted(path for path in input_directory.rglob("*.perfetto-trace") if path.is_file())
    traces = []
    for index, path in enumerate(trace_sources, len(benchmark_json) + 1):
        item = copy_artifact(path, raw, index)
        variant, scenario = trace_identity(path.name)
        item.update({"variant": variant, "scenario": scenario})
        traces.append(item)
    manifest = {"schema": 1, "benchmark_json": benchmark_json, "traces": traces}
    (output / "evidence-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                                                   encoding="utf-8")
    (output / "json-files.txt").write_text("".join(f"{item['path']}\n" for item in benchmark_json), encoding="utf-8")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-directory", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        manifest = collect(args.input_directory, args.output)
    except (EvidenceError, OSError) as error:
        print(f"evidence-collection: ERROR: {error}", file=sys.stderr)
        return 2
    print(f"Preserved {len(manifest['benchmark_json'])} JSON files and {len(manifest['traces'])} Perfetto traces.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
