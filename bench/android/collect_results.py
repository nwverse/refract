#!/usr/bin/env python3
"""Copy AndroidX JSON and Perfetto traces into an immutable per-run directory."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any


class EvidenceError(RuntimeError):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"),
                          object_pairs_hook=unique_keys)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"Cannot parse evidence JSON {path.name}: {error}") from error


def unique_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise EvidenceError(f"Duplicate evidence JSON key: {key}")
        result[key] = value
    return result


def perfetto_iterations(outputs: list[Any], repeat_iterations: int) -> list[int]:
    iterations = []
    for output in outputs:
        if not isinstance(output, dict) or output.get("type") != "PerfettoTrace":
            continue
        label = output.get("label")
        if not isinstance(label, str) or not label.startswith("Trace Iteration "):
            raise EvidenceError("Perfetto output has no iteration label")
        try:
            iteration = int(label.removeprefix("Trace Iteration "))
        except ValueError as error:
            raise EvidenceError("Perfetto output has an invalid iteration label") from error
        if iteration < 0 or iteration >= repeat_iterations:
            raise EvidenceError("Perfetto iteration is outside repeatIterations")
        iterations.append(iteration)
    if sorted(iterations) != list(range(repeat_iterations)):
        raise EvidenceError("Perfetto outputs must contain exactly one trace for every declared iteration")
    return iterations


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


def bind_traces(json_sources: list[Path], copied_json: list[dict[str, object]],
                traces: list[dict[str, object]], source_revision: str) -> None:
    """Bind exact AndroidX paths and its source payload; never construct either."""
    referenced = set()
    macro_identities = set()
    for json_source in json_sources:
        payload = load_json(json_source)
        context = payload.get("context") if isinstance(payload, dict) else None
        context_payload = context.get("payload") if isinstance(context, dict) else None
        if not isinstance(context_payload, dict) or context_payload.get(
                "refract.sourceRevision") != source_revision:
            raise EvidenceError("AndroidX source payload does not match the target probe")
    by_name = {}
    for trace in traces:
        by_name.setdefault(trace["source_name"], []).append(trace)
    for source, copied in zip(json_sources, copied_json):
        payload = load_json(source)
        if not isinstance(payload, dict) or not isinstance(payload.get("benchmarks"), list):
            raise EvidenceError("AndroidX macro JSON needs its top-level context and benchmarks array")
        benchmarks = payload["benchmarks"]
        for benchmark in benchmarks:
            if not isinstance(benchmark, dict) or benchmark.get("className") != "dev.refract.bench.test.SettingsMacrobenchmark":
                continue
            name = benchmark.get("name")
            if not isinstance(name, str):
                raise EvidenceError("Macro benchmark has no name")
            variant, scenario = trace_identity(name)
            if not variant or not scenario or (variant, scenario) in macro_identities:
                raise EvidenceError(f"Duplicate or unidentified macro benchmark: {name}")
            macro_identities.add((variant, scenario))
            outputs = benchmark.get("profilerOutputs")
            if not isinstance(outputs, list) or not outputs:
                raise EvidenceError(f"AndroidX JSON has no profilerOutputs for {name}")
            repeat_iterations = benchmark.get("repeatIterations")
            if not isinstance(repeat_iterations, int) or isinstance(repeat_iterations, bool) or repeat_iterations < 1:
                raise EvidenceError(f"AndroidX JSON has no valid repeatIterations for {name}")
            iterations = perfetto_iterations(outputs, repeat_iterations)
            trace_index = -1
            for output in outputs:
                if not isinstance(output, dict) or output.get("type") != "PerfettoTrace":
                    continue
                trace_index += 1
                filename = output.get("filename")
                if not isinstance(filename, str) or not filename or "\\" in filename:
                    raise EvidenceError(f"Invalid Perfetto filename for {name}")
                relative = Path(filename)
                if relative.is_absolute() or ".." in relative.parts or relative.as_posix() != filename:
                    raise EvidenceError(f"Perfetto path escapes the AndroidX output directory for {name}")
                matches = by_name.get(relative.as_posix(), [])
                if len(matches) != 1:
                    raise EvidenceError(f"Perfetto file is missing or ambiguous for {name}: {relative.as_posix()}")
                trace = matches[0]
                if trace["source_name"] in referenced:
                    raise EvidenceError(f"Perfetto file is claimed by multiple benchmark iterations: {relative.as_posix()}")
                trace.update({"variant": variant, "scenario": scenario})
                trace["androidx_benchmark"] = name
                trace["androidx_json"] = copied["path"]
                trace["iteration"] = iterations[trace_index]
                referenced.add(trace["source_name"])
    if macro_identities != {(variant, scenario) for variant in ("generated", "reference")
                            for scenario in ("startup", "scroll", "stateUpdate")}:
        raise EvidenceError("Complete macro evidence requires exactly six generated/reference scenario records")
    unreferenced = [trace["source_name"] for trace in traces if trace["source_name"] not in referenced]
    if unreferenced:
        raise EvidenceError("Perfetto trace is not referenced by AndroidX JSON; refusing to infer ownership")


def collect(input_directory: Path, output: Path, environment: Path | None = None) -> dict[str, object]:
    if not input_directory.is_dir():
        raise EvidenceError("AndroidX additional-output directory is absent; instrumentation did not produce evidence.")
    if environment is None:
        raise EvidenceError("Macro collection requires --environment; no partial report can be produced")
    output.mkdir(parents=True, exist_ok=True)
    if (output / "evidence-manifest.json").exists() or (output / "json-files.txt").exists():
        raise EvidenceError("Refusing to replace an existing evidence manifest; choose a new run directory.")
    staging = Path(tempfile.mkdtemp(prefix=".evidence-staging-", dir=output))
    published = False
    try:
        metadata = load_json(environment)
        source_revision = metadata.get("source_revision") if isinstance(metadata, dict) else None
        if not isinstance(source_revision, str) or metadata.get("status") != "ready" or metadata.get("emulator") is not True:
            raise EvidenceError("A verified target environment with a source revision is required")
        raw = staging / "raw"
        raw.mkdir()
        raw_environment = raw / "environment.json"
        shutil.copyfile(environment, raw_environment)
        environment_artifact = {"path": "raw/environment.json", "bytes": raw_environment.stat().st_size,
                                "sha256": digest(raw_environment)}
        json_sources = sorted(path for path in input_directory.rglob("*benchmarkData.json") if path.is_file())
        if not json_sources:
            raise EvidenceError("No AndroidX benchmark JSON was produced; this is not a passing run.")
        benchmark_json = [copy_artifact(path, raw, index) for index, path in enumerate(json_sources, 1)]
        trace_sources = sorted(path for path in input_directory.rglob("*.perfetto-trace") if path.is_file())
        traces = []
        for index, path in enumerate(trace_sources, len(benchmark_json) + 1):
            item = copy_artifact(path, raw, index)
            relative = path.relative_to(input_directory).as_posix()
            item.update({"source_name": relative})
            traces.append(item)
        bind_traces(json_sources, benchmark_json, traces, source_revision)
        manifest = {"schema": 1, "benchmark_json": benchmark_json, "traces": traces,
                    "environment": [environment_artifact]}
        (staging / "evidence-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                                                        encoding="utf-8")
        (staging / "json-files.txt").write_text("".join(f"{item['path']}\n" for item in benchmark_json),
                                                encoding="utf-8")
        # Publish each completed run artifact only after the whole binding passes.
        # A rejected or interrupted staging remains quarantined, never a valid manifest.
        raw_output = output / "raw"
        if raw_output.exists() and any(raw_output.iterdir()):
            raise EvidenceError("Refusing to publish over existing raw evidence")
        raw.rename(raw_output)
        (staging / "evidence-manifest.json").rename(output / "evidence-manifest.json")
        (staging / "json-files.txt").rename(output / "json-files.txt")
        published = True
        return manifest
    finally:
        if published:
            staging.rmdir()
        # Otherwise retain the unique staging directory as explicitly incomplete evidence.


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-directory", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--environment", type=Path, help="Verified target probe to preserve with the raw evidence")
    args = parser.parse_args(argv)
    try:
        manifest = collect(args.input_directory, args.output, args.environment)
    except (EvidenceError, OSError) as error:
        print(f"evidence-collection: ERROR: {error}", file=sys.stderr)
        return 2
    print(f"Preserved {len(manifest['benchmark_json'])} JSON files and {len(manifest['traces'])} Perfetto traces.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
