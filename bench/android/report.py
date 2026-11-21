#!/usr/bin/env python3
"""Normalize AndroidX benchmark output and compare paired generated/reference runs.

No third-party packages, network access, or repository-private values are needed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

HIGHER_IS_WORSE = {
    "startupMs",
    "timeMs",
    "timeToInitialDisplayMs",
    "timeToFullDisplayMs",
    "frameDurationCpuMs",
}

LOWER_IS_WORSE_ABSOLUTE_MS = 0.1
MACRO_SCENARIOS = ("startup", "scroll", "stateUpdate")
MACRO_MINIMUM_ITERATIONS = 10
MEMORY_METRICS = {
    "memoryRssAnonLastKb", "memoryRssFileLastKb", "memoryRssShmemLastKb",
    "memoryHeapSizeLastKb", "memoryGpuLastKb",
}
STARTUP_METRICS = {"timeToInitialDisplayMs", "timeToFullDisplayMs"}
SOURCE_TREE_VERIFIED = "HEAD matched and worktree clean after generated-source verification, release compilation and measurement"


class ReportError(ValueError):
    pass


def unique_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ReportError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


@dataclass(frozen=True)
class Measurement:
    key: tuple[str, str, str, str]
    metric: str
    unit: str
    values: list[float]
    sample_kind: str
    sample_count: int
    repeat_iterations: int
    context: dict[str, Any]
    profiler_outputs: Any


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def load_json(path: Path) -> Any:
    try:
        with path.open(encoding="utf-8") as stream:
            return json.load(stream, parse_constant=lambda constant: (_ for _ in ()).throw(
                ReportError(f"Non-finite JSON value in {path}: {constant}")
            ), object_pairs_hook=unique_keys)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ReportError(f"Cannot read {path}: {error}") from error


def samples(metrics: dict[str, Any], iterations: int) -> Iterable[tuple[str, str, list[float], int]]:
    for name, value in metrics.items():
        if not isinstance(value, dict):
            raise ReportError(f"Metric {name!r} has no sample object")
        if "runs" in value:
            runs = value["runs"]
            if not isinstance(runs, list) or not runs or not all(
                isinstance(number, (int, float)) and not isinstance(number, bool)
                and math.isfinite(number) for number in runs
            ):
                raise ReportError(f"Metric {name!r} must contain finite numeric runs")
            yield name, "native", [float(number) for number in runs], len(runs)
        elif all(key in value for key in ("minimum", "maximum", "median")):
            # Old aggregate-only reports have no p99 distribution. Preserve that
            # evidence limitation instead of labelling a median as a raw sample.
            median = value["median"]
            if not isinstance(median, (int, float)) or isinstance(median, bool) or not math.isfinite(median):
                raise ReportError(f"Metric {name!r} has an invalid aggregate median")
            yield name, "aggregate", [float(median)], iterations
        else:
            raise ReportError(f"Metric {name!r} has no runs or aggregate median")


def extract(payload: Any, source: Path) -> list[Measurement]:
    if isinstance(payload, list):
        benchmarks = payload
    elif isinstance(payload, dict) and isinstance(payload.get("benchmarks"), list):
        benchmarks = payload["benchmarks"]
    else:
        raise ReportError(f"{source} has no benchmarks array")
    output = []
    shared_context = payload.get("context") if isinstance(payload, dict) else None
    for benchmark in benchmarks:
        if not isinstance(benchmark, dict):
            raise ReportError(f"{source} contains a non-object benchmark")
        context = benchmark.get("context", shared_context)
        metrics = benchmark.get("metrics")
        if not isinstance(context, dict) or not isinstance(metrics, dict) or not metrics:
            raise ReportError(f"{source} has an incomplete benchmark record")
        name = benchmark.get("name")
        if not isinstance(name, str) or not name:
            raise ReportError(f"{source} has a benchmark without a name")
        class_name = benchmark.get("className")
        if class_name not in (
            "dev.refract.bench.test.SettingsMacrobenchmark",
            "dev.refract.bench.test.SettingsMicrobenchmark",
        ):
            raise ReportError(f"Unexpected benchmark className in {name!r}")
        kind = "Micro" if class_name.endswith("Microbenchmark") else "Macro"
        benchmark_name = name.removeprefix("EMULATOR_")
        suffix = benchmark_name.removeprefix(class_name + ".")
        if suffix == benchmark_name:
            suffix = benchmark_name
        if not suffix:
            raise ReportError(f"Unexpected benchmark name in {name!r}")
        method, separator, macro_scenario = suffix.partition(".")
        scenarios = {
            "generatedMacrobenchmark": ("generated", "scroll"),
            "referenceMacrobenchmark": ("reference", "scroll"),
            "generatedStartup": ("generated", "startup"),
            "referenceStartup": ("reference", "startup"),
            "generatedStateUpdate": ("generated", "stateUpdate"),
            "referenceStateUpdate": ("reference", "stateUpdate"),
            "generatedRowRecomposition": ("generated", "rowRecomposition"),
            "referenceRowRecomposition": ("reference", "rowRecomposition"),
        }
        if method not in scenarios or (separator and macro_scenario != "scroll"):
            raise ReportError(f"Cannot determine paired variant from {name!r}")
        variant, scenario = scenarios[method]
        if separator and method not in ("generatedMacrobenchmark", "referenceMacrobenchmark"):
            raise ReportError(f"Unexpected macrobenchmark variant in {name!r}")
        key = (kind, variant.lower(), scenario, name)
        iterations = benchmark.get("repeatIterations", benchmark.get("iterations"))
        if not isinstance(iterations, int) or isinstance(iterations, bool) or iterations < 1:
            raise ReportError(f"{source} has no valid iteration count for {name!r}")
        for metric, unit, values, sample_count in samples(metrics, iterations):
            output.append(Measurement(key, metric, unit, values, "runs" if unit == "native" else "aggregate",
                                      sample_count, iterations, context, benchmark.get("profilerOutputs")))
    if not output:
        raise ReportError(f"{source} has no benchmark metrics")
    return output


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        raise ReportError("Cannot take a percentile of zero samples")
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]


def normalize(measurement: Measurement) -> dict[str, Any]:
    metric = measurement.metric
    values = measurement.values
    unit = measurement.unit
    if metric in ("timeNs", "cpuTimeNs"):
        metric = "timeMs"
        values = [value / 1_000_000 for value in values]
        unit = "ms"
    return {
        "benchmark": measurement.key[2],
        "benchmark_kind": measurement.key[0],
        "variant": measurement.key[1],
        "metric": metric,
        "raw_unit": unit,
        "sample_kind": measurement.sample_kind,
        "sample_count": len(values),
        "repeat_iterations": measurement.repeat_iterations,
        "samples": values,
        "p50": percentile(values, 0.5),
        "p99": percentile(values, 0.99),
        "minimum": min(values),
        "maximum": max(values),
    }


def environment(context: dict[str, Any]) -> dict[str, Any]:
    build = context.get("build")
    device = context.get("device", {})
    if not isinstance(build, dict) or not isinstance(device, dict):
        raise ReportError("Benchmark context must include build information")
    device_info = {
        "model": build.get("model", "unknown"),
        "device": build.get("device", "unknown"),
        **device,
    }
    if context.get("emulator", True) is not True:
        raise ReportError("This report is explicitly for emulator runs; context.emulator must be true when present")
    return {
        "device": device_info,
        "build": build,
        "type": "emulator",
        "android_version": build.get("version", {}).get("sdk"),
    }


def required_pairs(rows: list[dict[str, Any]]) -> dict[tuple[str, str], dict[str, list[dict[str, Any]]]]:
    pairs: dict[tuple[str, str], dict[str, list[dict[str, Any]]]] = {}
    for row in rows:
        pairs.setdefault((row["benchmark"], row["metric"]), {}).setdefault(row["variant"], []).append(row)
    for (benchmark, metric), variants in pairs.items():
        for variant in ("generated", "reference"):
            matches = variants.get(variant, [])
            if len(matches) != 1:
                raise ReportError(f"Expected one {variant} result for {benchmark}.{metric}, found {len(matches)}")
            if matches[0]["sample_kind"] != variants.get("reference", [{}])[0].get("sample_kind", matches[0]["sample_kind"]):
                raise ReportError(f"Mixed raw and aggregate results for {benchmark}.{metric}")
    return pairs


def compare_pairs(rows: list[dict[str, Any]], percent: float, absolute_ms: float) -> list[dict[str, Any]]:
    results = []
    for (benchmark, metric), variants in sorted(required_pairs(rows).items()):
        generated = variants["generated"][0]
        reference = variants["reference"][0]
        if generated["raw_unit"] != reference["raw_unit"]:
            raise ReportError(f"Incompatible units for {benchmark}.{metric}")
        row = {
            "benchmark": benchmark,
            "metric": metric,
            "unit": "ms" if metric in HIGHER_IS_WORSE else generated["raw_unit"],
            "generated": generated,
            "reference": reference,
        }
        if metric in HIGHER_IS_WORSE:
            # Microbenchmark aggregate-only output has no p99 distribution.
            # Its raw runs, when present, are samples and remain gateable.
            quantiles = ("p50", "p99") if generated["sample_kind"] == "runs" else ("p50",)
            for quantile in quantiles:
                before, after = reference[quantile], generated[quantile]
                delta = after - before
                relative = delta / before * 100 if before != 0 else (0 if delta == 0 else math.inf)
                row[quantile] = {
                    "before": before,
                    "after": after,
                    "delta": delta,
                    "percent": relative,
                    "regressed": delta > absolute_ms and relative > percent,
                }
        results.append(row)
    return results


def markdown(report: dict[str, Any]) -> str:
    lines = [
        "# Android benchmark report",
        "",
        "**EMULATOR RESULTS — not device results.** Software virtualization and graphics are not representative of hardware performance.",
        "",
        "Lower-is-better regression limits: more than 5% AND more than 0.1 ms. All raw AndroidX files are retained.",
        "",
        "| Benchmark | Metric | Reference p50 | Generated p50 | Δ | Reference p99 | Generated p99 | Δ | Samples |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in report["comparisons"]:
        def values(variant: str, quantile: str) -> str:
            sample = row[variant]
            return f"{sample[quantile]:.3f} {sample['raw_unit']}"
        delta = row.get("p50", {})
        delta99 = row.get("p99", {})
        samples = f"{row['reference']['sample_count']} / {row['generated']['sample_count']}"
        lines.append(
            f"| {row['benchmark']} | {row['metric']} | {values('reference', 'p50')} | "
            f"{values('generated', 'p50')} | {delta.get('percent', 0):+.2f}% | "
            f"{values('reference', 'p99')} | {values('generated', 'p99')} | "
            f"{delta99.get('percent', 0):+.2f}% | {samples} |"
        )
    lines.extend(["", f"**Result: {report['status'].upper()}**", ""])
    return "\n".join(lines)


def validate_macro(measurements: list[Measurement], rows: list[dict[str, Any]],
                   traces: list[dict[str, Any]] | None, benchmark_json: list[dict[str, Any]]) -> None:
    """Reject partial macro evidence instead of passing whichever tests survived."""
    if traces is None:
        raise ReportError("Complete macro evidence requires a verified Perfetto trace manifest")
    expected_iterations = {}
    benchmark_identities = {}
    for measurement in measurements:
        if measurement.key[0] != "Macro":
            continue
        name = measurement.key[3]
        benchmark_identities[name] = (measurement.key[1], measurement.key[2])
        expected_iterations[name] = measurement.repeat_iterations
    for measurement in measurements:
        if measurement.key[0] != "Macro":
            continue
        outputs = measurement.profiler_outputs
        # Bind AndroidX's own profiler metadata to the retained trace, rather
        # than inferring evidence ownership from a filename alone.
        if not isinstance(outputs, list) or not any(
            isinstance(output, dict) and output.get("type") == "PerfettoTrace" and
            isinstance(output.get("filename"), str)
            for output in outputs
        ):
            raise ReportError(f"AndroidX JSON has no Perfetto filename for {measurement.key[3]}.{measurement.key[2]}")
    retained_json = {entry.get("path") for entry in benchmark_json}
    bound_iterations = set()
    for trace in traces:
        if not isinstance(trace, dict):
            raise ReportError("Perfetto evidence has an invalid manifest record")
        name = trace.get("androidx_benchmark")
        if name not in benchmark_identities or trace.get("androidx_json") not in retained_json:
            raise ReportError("Perfetto evidence is not bound to a retained AndroidX benchmark")
        if (trace.get("variant"), trace.get("scenario")) != benchmark_identities[name]:
            raise ReportError("Perfetto variant/scenario contradicts its AndroidX benchmark identity")
        iteration = trace.get("iteration")
        if not isinstance(iteration, int) or isinstance(iteration, bool) or \
                not 0 <= iteration < expected_iterations[name]:
            raise ReportError("Perfetto evidence has an invalid iteration binding")
        binding = (name, trace["androidx_json"], iteration)
        if binding in bound_iterations:
            raise ReportError("Perfetto evidence has a duplicate iteration binding")
        bound_iterations.add(binding)
    if len(bound_iterations) != len(traces):
        raise ReportError("Perfetto evidence has incomplete iteration bindings")
    for scenario in MACRO_SCENARIOS:
        for variant in ("generated", "reference"):
            selected = [row for row in rows if row["benchmark_kind"] == "Macro"
                        and row["benchmark"] == scenario and row["variant"] == variant]
            if not selected:
                raise ReportError(f"Complete macro evidence is missing {variant}.{scenario}")
            if any(row["sample_kind"] != "runs" or row["repeat_iterations"] < MACRO_MINIMUM_ITERATIONS
                   for row in selected):
                raise ReportError(f"Macro {variant}.{scenario} needs raw samples and at least ten iterations")
            if scenario == "startup":
                if not any(row["metric"] == "timeToInitialDisplayMs" for row in selected):
                    raise ReportError(f"Macro {variant}.startup is missing timeToInitialDisplayMs raw samples")
                startup_rows = [row for row in selected if row["metric"] in STARTUP_METRICS]
                if any(row["sample_count"] != row["repeat_iterations"] for row in startup_rows):
                    raise ReportError(f"Macro {variant}.startup needs one raw startup sample per declared iteration")
            else:
                if not any(row["metric"] == "frameDurationCpuMs" for row in selected):
                    raise ReportError(f"Macro {variant}.{scenario} is missing frameDurationCpuMs raw samples")
                if not any(row["metric"] in MEMORY_METRICS for row in selected):
                    raise ReportError(f"Macro {variant}.{scenario} is missing memory samples")
                memory_rows = [row for row in selected if row["metric"] in MEMORY_METRICS]
                if any(row["sample_count"] != row["repeat_iterations"] for row in memory_rows):
                    raise ReportError(f"Macro {variant}.{scenario} needs one memory sample per declared iteration")
            # AndroidX frame runs contain per-frame samples across all iterations;
            # their length is not the declared iteration count.
            if not any(trace.get("variant") == variant and trace.get("scenario") == scenario for trace in traces):
                raise ReportError(f"Perfetto evidence is missing {variant}.{scenario}")
            iteration_counts = {row["repeat_iterations"] for row in selected}
            if len(iteration_counts) != 1:
                raise ReportError(f"Macro {variant}.{scenario} metrics have inconsistent iteration counts")
            iterations = iteration_counts.pop()
            indices = [trace.get("iteration") for trace in traces
                       if trace.get("variant") == variant and trace.get("scenario") == scenario]
            if sorted(indices) != list(range(iterations)):
                raise ReportError(f"Macro {variant}.{scenario} needs one trace for every declared iteration")
        metrics = [{row["metric"] for row in rows if row["benchmark_kind"] == "Macro"
                    and row["benchmark"] == scenario and row["variant"] == variant}
                   for variant in ("generated", "reference")]
        if metrics[0] != metrics[1]:
            raise ReportError(f"Macro {scenario} variants have different metric sets")


def file_sha256(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def verify_evidence(manifest: Any, output: Path, inputs: list[Path],
                    require_environment: bool = False) -> dict[str, Any]:
    if not isinstance(manifest, dict) or manifest.get("schema") != 1:
        raise ReportError("Evidence manifest has an unsupported schema")
    verified = {}
    for kind in ("benchmark_json", "traces", "environment"):
        entries = manifest.get(kind)
        if not isinstance(entries, list) or not entries and (kind != "traces" or require_environment):
            raise ReportError(f"Evidence manifest has no valid {kind} list")
        seen = set()
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
                raise ReportError("Evidence manifest contains an invalid artifact")
            relative = Path(entry["path"])
            if relative.is_absolute() or ".." in relative.parts or relative.parts[0] != "raw":
                raise ReportError("Evidence paths must stay inside the run's raw directory")
            path = output / relative
            if entry["path"] in seen or not path.is_file():
                raise ReportError("Evidence file is duplicated or missing")
            if entry.get("bytes") != path.stat().st_size or entry.get("sha256") != file_sha256(path):
                raise ReportError(f"Evidence checksum mismatch: {entry['path']}")
            if kind == "traces" and entry["bytes"] == 0:
                raise ReportError(f"Empty Perfetto trace is not complete evidence: {entry['path']}")
            seen.add(entry["path"])
        verified[kind] = entries
    recorded = {(output / entry["path"]).resolve() for entry in verified["benchmark_json"]}
    if recorded != {path.resolve() for path in inputs}:
        raise ReportError("Report inputs do not exactly match the preserved AndroidX JSON manifest")
    return verified


def verify_source_provenance(contexts: set[str], metadata: dict[str, Any]) -> None:
    revision = metadata.get("source_revision")
    if not re.fullmatch(r"[0-9a-f]{40}", str(revision)):
        raise ReportError("Complete macro evidence requires a full source revision from the target probe")
    target = metadata.get("target")
    if not isinstance(target, dict):
        raise ReportError("Complete macro evidence requires a named probed target")
    for encoded in contexts:
        context = json.loads(encoded)
        payload = context.get("payload")
        if not isinstance(payload, dict) or payload.get("refract.sourceRevision") != revision:
            raise ReportError("AndroidX source provenance does not match the target-probed source revision")
        build = context.get("build")
        if not isinstance(build, dict) or not isinstance(build.get("version"), dict):
            raise ReportError("AndroidX target/build identity is incomplete")
        actual = {
            "model": build.get("model"), "device": build.get("device"),
            "build_id": build.get("id"), "sdk": build["version"].get("sdk"),
        }
        expected = {key: target.get(key) for key in actual}
        if actual != expected or any(value in (None, "") for value in actual.values()):
            raise ReportError("AndroidX target/build identity does not match the target probe")
        if context.get("compilationMode") != metadata.get("compilation_mode"):
            raise ReportError("AndroidX compilation mode does not match the probed benchmark configuration")


def make_report(inputs: list[Path], percent: float, absolute_ms: float,
                environment_metadata: dict[str, Any] | None = None, require_macro: bool = False,
                evidence: dict[str, Any] | None = None) -> dict[str, Any]:
    if not inputs:
        raise ReportError("At least one AndroidX JSON result is required")
    if environment_metadata is None:
        environment_metadata = {"emulator": True, "source": "unit-test fixture"}
    if require_macro and not re.fullmatch(r"[0-9a-f]{40}", str(environment_metadata.get("source_revision", ""))):
        raise ReportError("Complete macro evidence requires a full source revision from the target probe")
    if environment_metadata.get("emulator") is not True:
        raise ReportError("Report generation requires a verified emulator environment")
    if require_macro:
        if environment_metadata.get("status") != "ready" or \
                environment_metadata.get("source_tree") != SOURCE_TREE_VERIFIED:
            raise ReportError("Complete macro evidence requires an unchanged clean source tree")
        if len((evidence or {}).get("environment", [])) != 1 or \
                evidence["environment"][0].get("path") != "raw/environment.json":
            raise ReportError("Complete macro evidence requires its dedicated preserved environment")
    if percent < 0 or absolute_ms < 0 or not math.isfinite(percent) or not math.isfinite(absolute_ms):
        raise ReportError("Thresholds must be finite and non-negative")
    measurements = []
    for path in inputs:
        measurements.extend(extract(load_json(path), path))
    contexts = {canonical(measurement.context) for measurement in measurements}
    if len(contexts) != 1:
        raise ReportError("Refusing to compare different devices or build contexts")
    if require_macro:
        verify_source_provenance(contexts, environment_metadata)
    rows = [normalize(measurement) for measurement in measurements]
    if require_macro:
        validate_macro(measurements, rows, evidence.get("traces") if evidence else None,
                       (evidence or {}).get("benchmark_json", []))
    comparisons = compare_pairs(rows, percent, absolute_ms)
    failures = [comparison for comparison in comparisons if any(
        comparison.get(quantile, {}).get("regressed", False) for quantile in ("p50", "p99")
    )]
    return {
        "schema": 1,
        "platform": "android",
        "environment_label": "emulator",
        "device_result": False,
        "macro_evidence_required": require_macro,
        "artifact_integrity": "verified" if evidence else "not_requested",
        "environment": {**environment(measurements[0].context), "verification": environment_metadata},
        "threshold": {"relative_percent": percent, "absolute_ms": absolute_ms, "conjunction": "AND"},
        "measurements": rows,
        "comparisons": comparisons,
        "status": "fail" if failures else "pass",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", type=Path, nargs="+", help="AndroidX benchmark JSON files")
    parser.add_argument("--output", required=True, type=Path, help="Output directory for report.json/report.md")
    parser.add_argument("--threshold-percent", type=float, default=5.0)
    parser.add_argument("--threshold-ms", type=float, default=0.1)
    parser.add_argument("--environment", type=Path, help="JSON metadata recorded by the runner's emulator probe")
    parser.add_argument("--require-macro", action="store_true",
                        help="Require both variants of startup/scroll/stateUpdate, raw samples and Perfetto coverage")
    parser.add_argument("--evidence-manifest", type=Path,
                        help="Preserved JSON/trace manifest; required for complete macro evidence")
    args = parser.parse_args(argv)
    try:
        if args.require_macro and not args.evidence_manifest:
            raise ReportError("--require-macro also requires --evidence-manifest")
        evidence = verify_evidence(load_json(args.evidence_manifest), args.output, args.inputs,
                                   require_environment=args.require_macro) \
            if args.evidence_manifest else None
        if args.require_macro and args.environment:
            raise ReportError("Complete macro evidence reads its environment from the verified manifest")
        environment_path = args.environment
        if args.require_macro and evidence:
            entries = evidence["environment"]
            if len(entries) != 1:
                raise ReportError("Complete macro evidence needs exactly one preserved target environment")
            environment_path = args.output / entries[0]["path"]
        report = make_report(
            args.inputs,
            args.threshold_percent,
            args.threshold_ms,
            load_json(environment_path) if environment_path else None,
            require_macro=args.require_macro,
            evidence=evidence,
        )
    except ReportError as error:
        print(f"benchmark-report: ERROR: {error}", file=sys.stderr)
        return 2
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (args.output / "report.md").write_text(markdown(report), encoding="utf-8")
    print(markdown(report), end="")
    return 1 if report["status"] == "fail" else 0


if __name__ == "__main__":
    sys.exit(main())
