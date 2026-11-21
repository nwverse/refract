"""Fail-closed normalization of native paired performance evidence.

The input contract is intentionally small and platform-neutral, but native trace
provenance is not. Every timing sample has one variant/scenario/iteration and
one verified raw native metric or trace artifact. Empty, partial, cross-target
or incorrectly typed evidence is an error, not a passing report.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any

VARIANTS = ("generated", "reference")
SCENARIOS = ("startup", "scroll", "stateUpdate")
MINIMUM_ITERATIONS = 30
GATED_METRICS = {
    "startupMs",
    "frameDurationMs",
    "frameIntervalMs",
}
SCENARIO_METRICS = {
    "ios": {"startup": "startupMs", "scroll": "frameIntervalMs", "stateUpdate": "frameIntervalMs"},
    "harmonyos": {"startup": "startupMs", "scroll": "frameDurationMs", "stateUpdate": "frameDurationMs"},
}


class EvidenceError(ValueError):
    pass


def finite_number(value: Any, label: str, positive: bool = False) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise EvidenceError(f"{label} must be a finite number")
    result = float(value)
    if result < 0 or positive and result <= 0:
        raise EvidenceError(f"{label} must be {'positive' if positive else 'non-negative'}")
    return result


def text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value or len(value) > 4096 or any(
        character in value for character in ("\n", "\r", "\x00", "/", "\\")
    ):
        raise EvidenceError(f"{label} must be one bounded text value")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        raise EvidenceError("Cannot calculate a percentile of zero samples")
    # Keep the established nearest-rank gate. At the minimum sample count p99
    # is the maximum: a tail regression is not replaced by an average.
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def validate_environment(environment: Any, platform: str) -> dict[str, Any]:
    if not isinstance(environment, dict):
        raise EvidenceError("Environment must be an object")
    if environment.get("platform") != platform:
        raise EvidenceError(f"Environment platform must be {platform}")
    label = environment.get("target_label")
    if label not in ("DEVICE", "SIMULATOR", "EMULATOR"):
        raise EvidenceError("Target label must be DEVICE, SIMULATOR or EMULATOR")
    device = environment.get("device_result")
    if not isinstance(device, bool) or device != (label == "DEVICE"):
        raise EvidenceError("Target label and device_result disagree")
    required = ("source_revision", "toolchain", "build_configuration", "target", "commands")
    for key in required:
        if key not in environment:
            raise EvidenceError(f"Environment is missing {key}")
    revision = environment["source_revision"]
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise EvidenceError("Evidence needs a complete source revision")
    if not isinstance(environment["commands"], list) or not environment["commands"] or not all(
        isinstance(command, str) and command for command in environment["commands"]
    ):
        raise EvidenceError("Exact acquisition/analysis commands are required")
    for key in ("toolchain", "build_configuration"):
        if not isinstance(environment[key], dict) or not environment[key]:
            raise EvidenceError(f"{key} must be a nonempty object")
    target = environment["target"]
    if not isinstance(target, dict):
        raise EvidenceError("Target must identify model, OS and architecture")
    for key in ("model", "os_version", "architecture"):
        text(target.get(key), f"target.{key}")
    return environment


def artifact(entry: Any, root: Path, platform: str) -> tuple[dict[str, Any], str]:
    if not isinstance(entry, dict):
        raise EvidenceError("Every artifact must be an object")
    value = entry.get("path")
    if not isinstance(value, str) or not value or len(value) > 4096 or any(
        character in value for character in ("\n", "\r", "\x00", "\\")
    ):
        raise EvidenceError("artifact.path must be one bounded relative path")
    relative = value
    path = Path(relative)
    if path.is_absolute() or ".." in path.parts or path.parts[0] != "raw":
        raise EvidenceError("Artifacts must remain under raw/")
    kind = entry.get("kind")
    allowed = {
        "ios": ("xcresult", "xctrace", "xcode-metric-json"),
        "harmonyos": ("vendor-trace", "vendor-metric-json"),
    }[platform]
    if kind not in allowed:
        raise EvidenceError(f"Artifact kind {kind!r} is not a native {platform} artifact")
    absolute = root / path
    if not absolute.is_file() or absolute.is_symlink() or absolute.stat().st_size == 0:
        raise EvidenceError(f"Missing, linked or empty native artifact: {relative}")
    expected_size = entry.get("bytes")
    if isinstance(expected_size, bool) or not isinstance(expected_size, int) or expected_size != absolute.stat().st_size:
        raise EvidenceError(f"Artifact size mismatch: {relative}")
    if entry.get("sha256") != sha256(absolute):
        raise EvidenceError(f"Artifact checksum mismatch: {relative}")
    identity = (
        text(entry.get("variant"), "artifact.variant"),
        text(entry.get("scenario"), "artifact.scenario"),
        entry.get("iteration"),
    )
    if identity[0] not in VARIANTS or identity[1] not in SCENARIOS:
        raise EvidenceError("Artifact has an invalid variant/scenario")
    if isinstance(identity[2], bool) or not isinstance(identity[2], int) or identity[2] < 0:
        raise EvidenceError("Artifact iteration must be a nonnegative integer")
    # Native bundles remain opaque here. Their raw file plus the exact native
    # export command is retained; parsing a directory named .trace is forbidden.
    entry["resolved_path"] = absolute
    return entry, relative


def samples_for(measurement: dict[str, Any], artifacts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if set(measurement) - {"platform", "variant", "scenario", "iteration", "metric", "unit", "samples", "artifacts"}:
        raise EvidenceError("Measurement contains unknown fields; choose an explicit schema")
    if measurement.get("platform") not in ("ios", "harmonyos"):
        raise EvidenceError("Measurement has an unsupported platform")
    platform = measurement["platform"]
    variant = measurement.get("variant")
    scenario = measurement.get("scenario")
    iteration = measurement.get("iteration")
    if variant not in VARIANTS or scenario not in SCENARIOS:
        raise EvidenceError("Measurement has an invalid variant/scenario")
    if isinstance(iteration, bool) or not isinstance(iteration, int) or iteration < 0:
        raise EvidenceError("Measurement iteration must be a nonnegative integer")
    metric = measurement.get("metric")
    if metric not in GATED_METRICS:
        raise EvidenceError(f"Unsupported timing metric: {metric!r}")
    expected_metric = SCENARIO_METRICS[platform][scenario]
    if metric != expected_metric:
        raise EvidenceError(f"{platform}.{scenario} requires the native {expected_metric} contract")
    unit = measurement.get("unit")
    if unit != "ms":
        raise EvidenceError("Timing samples must be milliseconds; normalize units explicitly")
    raw = measurement.get("samples")
    if not isinstance(raw, list) or not raw:
        raise EvidenceError("Timing measurement must contain raw samples")
    values = [finite_number(value, "timing sample", positive=True) for value in raw]
    referenced = measurement.get("artifacts")
    if not isinstance(referenced, list) or not referenced or not all(isinstance(value, str) for value in referenced):
        raise EvidenceError("Every timing measurement must reference raw native evidence")
    matches = [artifact for artifact in artifacts if artifact["path"] in referenced]
    if len(matches) != len(referenced) or len({value for value in referenced}) != len(referenced):
        raise EvidenceError("Missing or ambiguous native evidence reference")
    for artifact in matches:
        if (artifact["variant"], artifact["scenario"], artifact["iteration"]) != (variant, scenario, iteration):
            raise EvidenceError("Timing sample is not bound to its variant/scenario/iteration")
    if platform == "ios" and sum(match["kind"] == "xcode-metric-json" for match in matches) != 1:
        raise EvidenceError("iOS timing requires exactly one xcode-metric-json from its variant/scenario/iteration")
    return [{
        "variant": variant, "scenario": scenario, "iteration": iteration,
        "metric": metric, "value": value, "artifacts": sorted(referenced),
    } for value in values]


def validate_resources(measurements: Any, artifacts: list[dict[str, Any]], platform: str) -> list[dict[str, Any]]:
    if not isinstance(measurements, list):
        raise EvidenceError("Resource measurements must be an array")
    output = []
    seen = set()
    for entry in measurements:
        if not isinstance(entry, dict) or entry.get("platform") != platform:
            raise EvidenceError("Resource measurement has the wrong platform")
        identity = (entry.get("variant"), entry.get("scenario"), entry.get("iteration"), entry.get("metric"))
        if identity[0] not in VARIANTS or identity[1] not in SCENARIOS or isinstance(identity[2], bool) \
                or not isinstance(identity[2], int) or identity[2] < 0:
            raise EvidenceError("Resource measurement identity is invalid")
        if identity in seen:
            raise EvidenceError("Duplicate resource measurement")
        seen.add(identity)
        if identity[3] not in ("residentMemoryBytes", "installedBinaryBytes"):
            raise EvidenceError("Unsupported resource metric")
        value = entry.get("bytes")
        if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
            raise EvidenceError("Memory and binary size require positive integer bytes")
        paths = entry.get("artifacts")
        if not isinstance(paths, list) or not paths:
            raise EvidenceError("Resource measurement has no native provenance")
        for path in paths:
            matches = [artifact for artifact in artifacts if artifact["path"] == path]
            if len(matches) != 1 or (matches[0]["variant"], matches[0]["scenario"], matches[0]["iteration"]) != identity[:3]:
                raise EvidenceError("Resource measurement has mismatched native provenance")
        output.append({"variant": identity[0], "scenario": identity[1], "iteration": identity[2],
                       "metric": identity[3], "bytes": value, "artifacts": sorted(paths)})
    return output


def make_report(manifest: Any, root: Path) -> dict[str, Any]:
    if not isinstance(manifest, dict) or manifest.get("schema") != 1:
        raise EvidenceError("Unsupported evidence schema")
    platform = manifest.get("platform")
    if platform not in ("ios", "harmonyos"):
        raise EvidenceError("Only explicit iOS or HarmonyOS evidence is accepted")
    environment = validate_environment(manifest.get("environment"), platform)
    entries = manifest.get("artifacts")
    if not isinstance(entries, list) or not entries:
        raise EvidenceError("No raw native artifacts")
    artifacts = []
    paths = set()
    for entry in entries:
        artifact, path = artifact_entry(entry, root, platform)
        if path in paths:
            raise EvidenceError("Duplicate native artifact")
        paths.add(path)
        artifacts.append(artifact)
    measurements = manifest.get("measurements")
    if not isinstance(measurements, list) or not measurements:
        raise EvidenceError("No raw measurements")
    samples = []
    for measurement in measurements:
        if not isinstance(measurement, dict) or measurement.get("platform") != platform:
            raise EvidenceError("Measurement platform disagrees with environment")
        samples.extend(samples_for(measurement, artifacts))
    resources = validate_resources(manifest.get("resources"), artifacts, platform)
    for scenario in ("scroll", "stateUpdate"):
        for variant in VARIANTS:
            for iteration in range(MINIMUM_ITERATIONS):
                memory = [resource for resource in resources if resource["metric"] == "residentMemoryBytes"
                          and resource["scenario"] == scenario and resource["variant"] == variant
                          and resource["iteration"] == iteration]
                if len(memory) != 1:
                    raise EvidenceError(f"Missing resident memory sample: {variant}.{scenario}.{iteration}")
    for variant in VARIANTS:
        for scenario in ("startup", "scroll", "stateUpdate"):
            sizes = [resource for resource in resources if resource["metric"] == "installedBinaryBytes"
                     and resource["scenario"] == scenario and resource["variant"] == variant
                     and resource["iteration"] == 0]
            if len(sizes) != 1:
                raise EvidenceError(f"Missing installed binary size: {variant}.{scenario}")
            if any(resource["metric"] == "installedBinaryBytes" and resource["variant"] == variant
                   and resource["bytes"] != sizes[0]["bytes"] for resource in resources):
                raise EvidenceError(f"Inconsistent installed binary size for {variant}")
    comparisons = []
    for scenario in SCENARIOS:
        metric = SCENARIO_METRICS[platform][scenario]
        for iteration in range(MINIMUM_ITERATIONS):
            for variant in VARIANTS:
                matching = [sample for sample in samples if sample["scenario"] == scenario
                            and sample["metric"] == metric and sample["iteration"] == iteration
                            and sample["variant"] == variant]
                if len(matching) != 1:
                    raise EvidenceError(f"Missing or duplicate raw sample: {variant}.{scenario}.{metric}.iteration{iteration}")
                traces = [artifact for artifact in artifacts if artifact["scenario"] == scenario
                          and artifact["variant"] == variant and artifact["iteration"] == iteration
                          and artifact["kind"] in ("xctrace", "vendor-trace")]
                if len(traces) != 1:
                    raise EvidenceError(f"Need exactly one native trace per iteration: {variant}.{scenario}.{iteration}")
                if traces[0]["path"] not in {path for sample in samples if sample["scenario"] == scenario
                                            and sample["metric"] == metric and sample["iteration"] == iteration
                                            and sample["variant"] == variant for path in sample["artifacts"]}:
                    raise EvidenceError(f"Native trace is not referenced by its timing sample: {variant}.{scenario}.{iteration}")
        values = {}
        for variant in VARIANTS:
            values[variant] = [sample["value"] for sample in samples if sample["scenario"] == scenario
                               and sample["metric"] == metric and sample["variant"] == variant]
        quantiles = {}
        regressed = False
        for quantile, fraction in (("p50", 0.5), ("p99", 0.99)):
            reference = percentile(values["reference"], fraction)
            generated = percentile(values["generated"], fraction)
            delta = generated - reference
            relative = delta / reference * 100 if reference else math.inf if delta else 0
            failed = delta > 0.1 and relative > 5.0
            regressed = regressed or failed
            quantiles[quantile] = {"reference": reference, "generated": generated, "delta": delta,
                                   "percent": relative, "regressed": failed}
        comparisons.append({"scenario": scenario, "metric": metric, "unit": "ms", **quantiles})
    return {
        "schema": 1,
        "platform": platform,
        "target_label": environment["target_label"],
        "device_result": environment["device_result"],
        "physical_device_gate_satisfied": environment["device_result"],
        "environment": environment,
        "artifact_integrity": "verified",
        "threshold": {"relative_percent": 5.0, "absolute_ms": 0.1, "conjunction": "AND"},
        "comparisons": comparisons,
        "resources": resources,
        "status": "fail" if any(row["p50"]["regressed"] or row["p99"]["regressed"] for row in comparisons) else "pass",
    }


def artifact_entry(entry: Any, root: Path, platform: str) -> tuple[dict[str, Any], str]:
    result, path = artifact(entry, root, platform)
    return result, path


def markdown(report: dict[str, Any]) -> str:
    label = report["target_label"]
    lines = [
        f"# {report['platform'].upper()} paired benchmark report",
        "",
        f"**{label} RESULTS — {'physical-device evidence' if report['device_result'] else 'not device results'}.**",
        "The physical-device gate remains open. Do not extrapolate to another OS or target.",
        "",
        "Lower-is-better screening: greater than 5% AND greater than 0.1 ms at p50 or p99. All raw native artifacts are checksummed.",
        "",
        "| Scenario | Metric | Reference p50 | Generated p50 | Δ | Reference p99 | Generated p99 | Δ |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in report["comparisons"]:
        lines.append(
            f"| {row['scenario']} | {row['metric']} | {row['p50']['reference']:.3f} | "
            f"{row['p50']['generated']:.3f} | {row['p50']['percent']:+.2f}% | "
            f"{row['p99']['reference']:.3f} | {row['p99']['generated']:.3f} | {row['p99']['percent']:+.2f}% |"
        )
    lines += ["", f"**Result: {report['status'].upper()}**", ""]
    return "\n".join(lines)
