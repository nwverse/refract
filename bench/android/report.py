#!/usr/bin/env python3
"""Normalize AndroidX benchmark output and compare paired generated/reference runs.

No third-party packages, network access, or repository-private values are needed.
"""

from __future__ import annotations

import argparse
import json
import math
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


class ReportError(ValueError):
    pass


@dataclass(frozen=True)
class Measurement:
    key: tuple[str, str, str, str]
    metric: str
    unit: str
    values: list[float]
    sample_kind: str
    sample_count: int
    context: dict[str, Any]


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def load_json(path: Path) -> Any:
    try:
        with path.open(encoding="utf-8") as stream:
            return json.load(stream, parse_constant=lambda constant: (_ for _ in ()).throw(
                ReportError(f"Non-finite JSON value in {path}: {constant}")
            ))
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
    for benchmark in benchmarks:
        if not isinstance(benchmark, dict):
            raise ReportError(f"{source} contains a non-object benchmark")
        context = benchmark.get("context")
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
        suffix = name.removeprefix(class_name + ".")
        if suffix == name or not suffix:
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
        key = (kind, variant.lower(), scenario, variant)
        iterations = benchmark.get("repeatIterations", benchmark.get("iterations"))
        if not isinstance(iterations, int) or iterations < 1:
            raise ReportError(f"{source} has no valid iteration count for {name!r}")
        for metric, unit, values, sample_count in samples(metrics, iterations):
            output.append(Measurement(key, metric, unit, values, "runs" if unit == "native" else "aggregate", sample_count, context))
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
        "sample_count": measurement.sample_count,
        "samples": values,
        "p50": percentile(values, 0.5),
        "p99": percentile(values, 0.99),
        "minimum": min(values),
        "maximum": max(values),
    }


def environment(context: dict[str, Any]) -> dict[str, Any]:
    build = context.get("build")
    device = context.get("device")
    if not isinstance(build, dict) or not isinstance(device, dict):
        raise ReportError("Benchmark context must include build and device objects")
    if context.get("emulator") is not True:
        raise ReportError("This report is explicitly for emulator runs; context.emulator must be true")
    return {
        "device": device,
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
            # AndroidX Microbenchmark usually persists only aggregate statistics.
            # Do not turn its median into a fictitious p99 gate; macrobenchmark
            # frame/startup samples carry the strict latency comparisons.
            if generated["benchmark_kind"] == "Micro":
                row["comparison_only"] = True
                results.append(row)
                continue
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


def make_report(inputs: list[Path], percent: float, absolute_ms: float) -> dict[str, Any]:
    if not inputs:
        raise ReportError("At least one AndroidX JSON result is required")
    if percent < 0 or absolute_ms < 0 or not math.isfinite(percent) or not math.isfinite(absolute_ms):
        raise ReportError("Thresholds must be finite and non-negative")
    measurements = []
    for path in inputs:
        measurements.extend(extract(load_json(path), path))
    contexts = {canonical(measurement.context) for measurement in measurements}
    if len(contexts) != 1:
        raise ReportError("Refusing to compare different devices or build contexts")
    rows = [normalize(measurement) for measurement in measurements]
    comparisons = compare_pairs(rows, percent, absolute_ms)
    failures = [comparison for comparison in comparisons if any(
        comparison.get(quantile, {}).get("regressed", False) for quantile in ("p50", "p99")
    )]
    return {
        "schema": 1,
        "platform": "android",
        "environment_label": "emulator",
        "device_result": False,
        "environment": environment(measurements[0].context),
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
    args = parser.parse_args(argv)
    try:
        report = make_report(args.inputs, args.threshold_percent, args.threshold_ms)
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
