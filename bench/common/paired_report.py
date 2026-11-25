"""Fail-closed normalization of native paired performance evidence.

The input contract is intentionally small and platform-neutral, but native trace
provenance is not. Every timing has one variant/scenario/iteration from 2...30
and one native duration or declared frame-interval reduction. Empty, partial,
cross-revision or incorrectly typed evidence is an error, not a passing report.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any
from build_provenance import original_build_provenance

VARIANTS = ("generated", "reference")
SCENARIOS = ("startup", "scroll", "stateUpdate")
MINIMUM_ITERATIONS = 30
ITERATIONS = range(2, 31)
RESOURCE_METRICS = ("residentMemoryBytes", "installedBinaryBytes")
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
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise EvidenceError(f"{label} must be a finite number")
    try:
        result = float(value)
    except (OverflowError, ValueError) as error:
        raise EvidenceError(f"{label} must be a finite number") from error
    if not math.isfinite(result):
        raise EvidenceError(f"{label} must be a finite number")
    if result < 0 or positive and result <= 0:
        raise EvidenceError(f"{label} must be {'positive' if positive else 'non-negative'}")
    return result


def bounded_text(value: Any, label: str, *, path: bool = False) -> str:
    if (not isinstance(value, str) or not value or len(value) > 4096
            or any(character in value for character in ("\n", "\r", "\x00"))):
        raise EvidenceError(f"{label} must be one bounded text value")
    if not path and any(character in value for character in ("/", "\\")):
        raise EvidenceError(f"{label} must be one bounded text value")
    return value


def text(value: Any, label: str) -> str:
    return bounded_text(value, label)


def sha256_text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
        raise EvidenceError(f"{label} must be a lowercase SHA-256")
    return value


def revision_text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{40}", value):
        raise EvidenceError(f"{label} requires a complete source revision")
    return value


def checked_iteration(value: Any, label: str = "iteration") -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value not in ITERATIONS:
        raise EvidenceError(f"{label} must be an integer in 2...30; never renumber native evidence")
    return value


def native_json(artifact: dict[str, Any]) -> dict[str, Any]:
    """Read a bounded JSON export only after its ordinary-file checksum passed."""
    try:
        if artifact["resolved_path"].stat().st_size > 16 * 1024 * 1024:
            raise EvidenceError(f"Native JSON export exceeds its size bound: {artifact['path']}")
        value = json.loads(artifact["resolved_path"].read_text(encoding="utf-8"),
                           parse_constant=lambda constant: (_ for _ in ()).throw(
                               EvidenceError(f"Non-finite native JSON value: {constant}")))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"Cannot read native JSON export {artifact['path']}: {error}") from error
    if not isinstance(value, dict):
        raise EvidenceError(f"Native JSON export must be an object: {artifact['path']}")
    return value


def raw_identity(payload: dict[str, Any], identity: tuple[str, str, int], revision: str) -> None:
    variant, scenario, iteration = identity
    expected = {"variant": variant, "scenario": scenario, "iteration": iteration, "sourceRevision": revision}
    for key, wanted in expected.items():
        if key == "iteration":
            checked_iteration(payload.get(key), "Native export iteration")
        if payload.get(key) != wanted:
            raise EvidenceError(f"Native export {key} does not match its artifact identity")


def duration_value(value: Any, label: str, unit: str = "ms") -> float:
    if not isinstance(value, dict):
        raise EvidenceError(f"{label} must be a duration object, not a timestamp")
    if value.get("unit") != unit or value.get("definition") != "XCTApplicationLaunchMetric":
        raise EvidenceError("iOS startup requires a native XCTApplicationLaunchMetric duration in milliseconds")
    if value.get("timestamp") is not None or "firstDisplay" in value:
        raise EvidenceError("A firstDisplay timestamp is not an application launch duration")
    return finite_number(value.get("duration_ms"), "native launch duration", positive=True)


def selected_duration(payload: dict[str, Any], identity: tuple[str, str, int], revision: str,
                      selector: Any) -> float:
    if identity[1] != "startup":
        raise EvidenceError("The selected launch metric must belong to startup")
    measurements = payload.get("measurements")
    if not isinstance(measurements, list) or not measurements:
        raise EvidenceError("Native metrics export contains no measurements")
    if type(selector) is not dict or set(selector) != {"index", "value_sha256"} \
            or type(selector["index"]) is not int:
        raise EvidenceError("Native startup selection requires an explicit measurement index and SHA-256")
    for entry in measurements:
        if not isinstance(entry, dict):
            raise EvidenceError("Native metric measurements must be objects")
        raw_identity(entry, identity, revision)
    if selector["index"] not in range(len(measurements)):
        raise EvidenceError("Native startup measurement index is outside the retained export")
    selected = measurements[selector["index"]]
    canonical = json.dumps(selected, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    if hashlib.sha256(canonical).hexdigest() != sha256_text(selector["value_sha256"], "metric_selector.value_sha256"):
        raise EvidenceError("Native startup selector checksum does not match the retained measurement")
    if selected.get("metric") != "XCTApplicationLaunchMetric":
        raise EvidenceError("The selected native metric is not XCTApplicationLaunchMetric")
    return duration_value(selected.get("value"), "native startup duration")


def checked_startup_value(payload: dict[str, Any], identity: tuple[str, str, int], revision: str,
                          selector: Any) -> float:
    if "measurements" in payload:
        return selected_duration(payload, identity, revision, selector)
    if "firstDisplay" in payload or "timestamp" in payload:
        raise EvidenceError("A firstDisplay timestamp is not an application launch duration")
    required = {"sourceRevision", "variant", "scenario", "iteration", "metric", "unit", "durationMs",
                "nativeMeasurement", "nativeMeasurementSha256"}
    if selector is not None or set(payload) != required:
        raise EvidenceError("Startup requires a checksummed native XCTApplicationLaunchMetric measurement")
    raw_identity(payload, identity, revision)
    if payload.get("metric") != "XCTApplicationLaunchMetric" or payload.get("unit") != "ms":
        raise EvidenceError("iOS startup requires the actual XCTApplicationLaunchMetric millisecond duration")
    native = payload["nativeMeasurement"]
    if not isinstance(native, dict) or set(native) != {"sourceRevision", "variant", "scenario", "iteration",
                                                        "metric", "unit", "durationMs"}:
        raise EvidenceError("The retained native launch measurement must be explicit")
    canonical = json.dumps(native, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    if hashlib.sha256(canonical).hexdigest() != sha256_text(payload["nativeMeasurementSha256"],
                                                            "nativeMeasurementSha256"):
        raise EvidenceError("The retained native launch measurement checksum does not match")
    raw_identity(native, identity, revision)
    value = finite_number(native.get("durationMs"), "native launch duration", positive=True)
    if value != finite_number(payload.get("durationMs"), "extracted launch duration", positive=True):
        raise EvidenceError("Extracted launch duration differs from the retained native measurement")
    return value


def checked_frame_samples(payload: dict[str, Any], identity: tuple[str, str, int], revision: str,
                          pid: Any, platform: str) -> list[float]:
    raw_identity(payload, identity, revision)
    if (type(payload.get("schema")) is not int or payload["schema"] != 1
            or type(payload.get("session")) is not int or type(pid) is not int or pid <= 0
            or type(payload.get("pid")) is not int or payload["pid"] <= 0 or payload["pid"] != pid
            or type(payload.get("completedIterations")) is not int or payload["completedIterations"] != 1
            or type(payload.get("recordedIteration")) is not int
            or payload["recordedIteration"] != identity[2]):
        raise EvidenceError("Native frame packet does not bind its selected session, process and iteration")
    field = "frameIntervalMs" if platform == "ios" else "frameDurationMs"
    label = "CADisplayLink interval" if platform == "ios" else "frame duration"
    samples = payload.get(field)
    tags = payload.get("iterationByFrame")
    if (not isinstance(samples, list) or not 0 < len(samples) <= 4096
            or not isinstance(tags, list) or len(tags) != len(samples)
            or any(type(tag) is not int or tag != identity[2] for tag in tags)):
        raise EvidenceError(f"Native {label} samples and iteration tags must be complete and bounded")
    return [finite_number(value, f"native {label}", positive=True) for value in samples]


def checked_resource_value(artifact: dict[str, Any], metric: str, revision: str, pid: Any) -> int:
    payload = native_json(artifact)
    raw_identity(payload, (artifact["variant"], artifact["scenario"], artifact["iteration"]), revision)
    required = {"sourceRevision", "variant", "scenario", "iteration", "metric", "bytes", "unit"}
    if metric == "residentMemoryBytes":
        required |= {"pid"}
        if type(payload.get("pid")) is not int or payload["pid"] != pid:
            raise EvidenceError("Native memory export PID does not match its iteration")
    if set(payload) != required or payload.get("unit") != "bytes":
        raise EvidenceError("Native resource export requires one explicit identity and byte value")
    if payload.get("metric") != metric:
        raise EvidenceError("Native resource export metric does not match its declared resource")
    value = payload.get("bytes")
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise EvidenceError("Native resource export requires positive integer bytes")
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
    required = ("source_revision", "build_provenance", "toolchain", "build_configuration", "target", "commands")
    for key in required:
        if key not in environment:
            raise EvidenceError(f"Environment is missing {key}")
    revision_text(environment["source_revision"], "Environment")
    build_provenance = environment["build_provenance"]
    if not isinstance(build_provenance, dict) or set(build_provenance) != {"path", "sha256"}:
        raise EvidenceError("Environment build_provenance requires exactly path and sha256")
    bounded_text(build_provenance["path"], "build_provenance.path", path=True)
    if Path(build_provenance["path"]).parts[0] != "raw" or ".." in Path(build_provenance["path"]).parts \
            or Path(build_provenance["path"]).is_absolute() or "\\" in build_provenance["path"]:
        raise EvidenceError("Build provenance must remain under raw/")
    sha256_text(build_provenance["sha256"], "build_provenance.sha256")
    if not isinstance(environment["commands"], list) or not environment["commands"] or not all(
        isinstance(command, str) and command for command in environment["commands"]
    ):
        raise EvidenceError("Exact acquisition/analysis commands are required")
    for command in environment["commands"]:
        bounded_text(command, "environment.commands")
    for key in ("toolchain", "build_configuration"):
        if not isinstance(environment[key], dict) or not environment[key]:
            raise EvidenceError(f"{key} must be a nonempty object")
    configuration = environment["build_configuration"]
    if platform == "ios" and (set(configuration) != {"name", "target", "derived_data"}
                              or configuration.get("name") != "Release"
                              or configuration.get("target") != "iphonesimulator"):
        raise EvidenceError("iOS requires explicit Release/iphonesimulator build-producer configuration")
    if platform == "ios":
        derived_data = configuration.get("derived_data")
        if not isinstance(derived_data, str):
            raise EvidenceError("iOS build producer requires a retained DerivedData path")
        bounded_text(derived_data, "build_configuration.derived_data", path=True)
        path = Path(derived_data)
        if path.is_absolute() or ".." in path.parts or "\\" in derived_data:
            raise EvidenceError("iOS DerivedData must be a relative path without traversal")
    target = environment["target"]
    if not isinstance(target, dict):
        raise EvidenceError("Target must identify model, OS and architecture")
    for key in ("model", "os_version", "architecture"):
        text(target.get(key), f"target.{key}")
    return environment


def artifact(entry: Any, root: Path, platform: str, environment: dict[str, Any]) -> tuple[dict[str, Any], str]:
    if not isinstance(entry, dict):
        raise EvidenceError("Every artifact must be an object")
    expected_fields = {"path", "kind", "role", "variant", "scenario", "iteration", "bytes", "sha256", "source_revision",
                       "build_provenance_sha256"}
    if set(entry) != expected_fields:
        raise EvidenceError("Artifact requires an explicit revision-bound schema 2 identity")
    value = bounded_text(entry["path"], "artifact.path", path=True)
    relative = value
    path = Path(relative)
    if path.is_absolute() or ".." in path.parts or path.parts[0] != "raw" or "\\" in value:
        raise EvidenceError("Artifacts must remain under raw/")
    kind = entry["kind"]
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
    if entry.get("sha256") != sha256_text(entry.get("sha256"), "artifact.sha256") or entry["sha256"] != sha256(absolute):
        raise EvidenceError(f"Artifact checksum mismatch: {relative}")
    identity = (
        text(entry["variant"], "artifact.variant"),
        text(entry["scenario"], "artifact.scenario"),
        checked_iteration(entry["iteration"], "Artifact iteration"),
    )
    role = entry["role"]
    if role not in ("timing", "profiler", "memory", "binary", "build-provenance"):
        raise EvidenceError("Artifact has an unsupported native evidence role")
    trace_kind = {"ios": "xctrace", "harmonyos": "vendor-trace"}[platform]
    if role == "profiler" and kind != trace_kind:
        raise EvidenceError(f"A profiler role requires the native {trace_kind} trace kind")
    if role == "build-provenance":
        if identity != ("shared", "build", 2):
            raise EvidenceError("Build provenance uses shared/build identity and a non-timing sentinel iteration")
    elif identity[0] not in VARIANTS or identity[1] not in SCENARIOS:
        raise EvidenceError("Artifact has an invalid variant/scenario")
    if (revision_text(entry["source_revision"], "Artifact") != environment["source_revision"]
            or entry["build_provenance_sha256"] != environment["build_provenance"]["sha256"]):
        raise EvidenceError("Artifact cannot backfill another revision or build")
    # Native bundles remain opaque here. Their raw file plus the exact native
    # export command is retained; parsing a directory named .trace is forbidden.
    entry = dict(entry)
    entry["resolved_path"] = absolute
    return entry, relative


def bundle_relative_path(value: Any, label: str) -> str:
    path = bounded_text(value, label, path=True)
    parsed = Path(path)
    if parsed.is_absolute() or ".." in parsed.parts or "." in parsed.parts or "\\" in path:
        raise EvidenceError("Build product file paths must be bundle-relative")
    return path


def checked_ios_build_provenance(payload: dict[str, Any], environment: dict[str, Any], root: Path) -> None:
    """Compare the complete canonical identity with recomputed original products."""
    configuration = environment["build_configuration"]
    if (environment["target_label"] != "SIMULATOR" or payload.get("configuration") != "Release-iphonesimulator"
            or set(payload) != {"schema", "source_revision", "configuration", "source_xctestrun", "products"}):
        raise EvidenceError("iOS build provenance does not match the existing producer and build destination")
    derived_data = root / configuration["derived_data"]
    try:
        current = root.resolve(strict=True)
        if not current.is_dir():
            raise EvidenceError("Evidence root must be a real directory")
        for part in Path(configuration["derived_data"]).parts:
            current = current / part
            if current.is_symlink():
                raise EvidenceError("iOS DerivedData and its ancestors must not be symbolic links")
        derived_data = current.resolve(strict=True)
    except OSError as error:
        raise EvidenceError(f"Cannot resolve the original iOS DerivedData: {error}") from error
    if not derived_data.is_dir():
        raise EvidenceError("iOS original DerivedData must be a real retained directory")
    try:
        original = original_build_provenance(derived_data, environment["source_revision"])
    except (OSError, TypeError, ValueError, KeyError) as error:
        raise EvidenceError(f"Cannot recompute original iOS build provenance: {error}") from error
    if payload != original:
        raise EvidenceError("iOS xctestrun or product identity differs from the original build products")


def checked_build_provenance(artifact: dict[str, Any], environment: dict[str, Any], root: Path) -> None:
    payload = native_json(artifact)
    if (payload.get("schema") != 1 or payload.get("source_revision") != environment["source_revision"]
            or type(payload.get("products")) is not dict):
        raise EvidenceError("Build provenance's internal revision or configuration does not match the environment")
    if environment["platform"] == "ios":
        checked_ios_build_provenance(payload, environment, root)
        return
    if (payload.get("configuration") != environment["build_configuration"].get("name")
            or set(payload) != {"schema", "source_revision", "configuration", "products"}):
        raise EvidenceError("Build provenance's internal revision or configuration does not match the environment")
    products = payload["products"]
    for variant in VARIANTS:
        product = products.get(variant)
        if not isinstance(product, dict):
            raise EvidenceError(f"Build provenance is missing the {variant} product identity")
        if set(product) != {"bundle", "files"} or not isinstance(product["files"], list) or not product["files"]:
            raise EvidenceError(f"Build provenance requires {variant} bundle files")
        text(product["bundle"], "product.bundle")
        for entry in product["files"]:
            if not isinstance(entry, dict) or set(entry) != {"path", "bytes", "sha256"}:
                raise EvidenceError("Build product files need bounded path, byte and checksum identities")
            bundle_relative_path(entry["path"], "product.path")
            if type(entry["bytes"]) is not int or entry["bytes"] <= 0:
                raise EvidenceError("Build product files require positive byte sizes")
            sha256_text(entry["sha256"], "product.sha256")
    for variant in VARIANTS:
        product = products[variant]
        prefix = f"{variant}/"
        if any(not entry["path"].startswith(prefix) for entry in product["files"]):
            raise EvidenceError("Build product identity is not owned by its declared variant")
    if any(products[first]["files"] == products[second]["files"]
           for first in VARIANTS for second in VARIANTS if first != second):
        raise EvidenceError("Generated and reference products cannot share the same product identity")


def samples_for(measurement: dict[str, Any], artifacts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if set(measurement) - {"platform", "variant", "scenario", "iteration", "metric", "unit", "value", "definition",
                           "aggregation", "native_pid", "metric_selector", "artifacts"}:
        raise EvidenceError("Measurement contains unknown fields; choose an explicit schema")
    if measurement.get("platform") not in ("ios", "harmonyos"):
        raise EvidenceError("Measurement has an unsupported platform")
    platform = measurement["platform"]
    variant = measurement.get("variant")
    scenario = measurement.get("scenario")
    if variant not in VARIANTS or scenario not in SCENARIOS:
        raise EvidenceError("Measurement has an invalid variant/scenario")
    iteration = checked_iteration(measurement.get("iteration"), "Measurement iteration")
    metric = measurement.get("metric")
    if metric not in GATED_METRICS:
        raise EvidenceError(f"Unsupported timing metric: {metric!r}")
    expected_metric = SCENARIO_METRICS[platform][scenario]
    if metric != expected_metric:
        raise EvidenceError(f"{platform}.{scenario} requires the native {expected_metric} contract")
    unit = measurement.get("unit")
    if unit != "ms":
        raise EvidenceError("Timing values must be milliseconds; normalize units explicitly")
    value = finite_number(measurement.get("value"), "timing value", positive=True)
    definition = measurement.get("definition")
    definitions = {
        "ios": {"startupMs": "XCTApplicationLaunchMetric", "frameIntervalMs": "CADisplayLink.targetTimestamp-timestamp"},
        "harmonyos": {"startupMs": "native-launch-duration", "frameDurationMs": "native-frame-duration"},
    }
    if definition != definitions[platform][metric]:
        raise EvidenceError(f"{platform}.{scenario} requires the declared {definitions[platform][metric]} definition; "
                            "firstDisplay is not a launch duration")
    aggregation = measurement.get("aggregation")
    if "metric_selector" in measurement and (platform != "ios" or scenario != "startup"):
        raise EvidenceError("metric_selector is supported only for an iOS startup measurement selection")
    if scenario == "startup":
        forbidden = ("aggregation", "source_samples", "native_pid")
        if any(measurement.get(key) is not None for key in forbidden):
            raise EvidenceError("Startup requires one scalar native launch duration, not a frame-series reduction")
    else:
        if aggregation != "p99":
            raise EvidenceError("Frame intervals require an explicit per-iteration p99 reduction")
        if any(measurement.get(key) is not None for key in ("launch_start_timestamp_ms", "first_frame_timestamp_ms",
                                                            "timestamp_unit", "metric_selector")):
            raise EvidenceError("Frame scenarios cannot mix launch timestamps with display intervals")
    referenced = measurement.get("artifacts")
    if not isinstance(referenced, list) or not referenced or not all(isinstance(value, str) for value in referenced):
        raise EvidenceError("Every timing measurement must reference raw native evidence")
    matches = [artifact for artifact in artifacts if artifact["path"] in referenced]
    if len(matches) != len(referenced) or len({value for value in referenced}) != len(referenced):
        raise EvidenceError("Missing or ambiguous native evidence reference")
    for artifact in matches:
        if (artifact["variant"], artifact["scenario"], artifact["iteration"]) != (variant, scenario, iteration):
            raise EvidenceError("Timing sample is not bound to its variant/scenario/iteration")
    timing = [match for match in matches if match["role"] == "timing"]
    if len(timing) != 1:
        raise EvidenceError("Timing requires exactly one native metric export")
    raw = native_json(timing[0])
    identity = (variant, scenario, iteration)
    revision = timing[0]["source_revision"]
    if platform == "ios" and scenario == "startup":
        value = checked_startup_value(raw, identity, revision, measurement.get("metric_selector"))
    elif scenario == "startup":
        if set(raw) != {"sourceRevision", "variant", "scenario", "iteration", "metric", "timestampUnit",
                        "launchStartTimestamp", "firstFrameTimestamp"}:
            raise EvidenceError("HarmonyOS startup requires explicit native launch and first-frame timestamps")
        raw_identity(raw, identity, revision)
        if raw["metric"] != "native-launch-duration" or raw["timestampUnit"] != "ms":
            raise EvidenceError("HarmonyOS startup timestamps must use native milliseconds")
        start = finite_number(raw["launchStartTimestamp"], "native launch timestamp", positive=True)
        first_frame = finite_number(raw["firstFrameTimestamp"], "native first-frame timestamp", positive=True)
        value = finite_number(first_frame - start, "native launch duration", positive=True)
    else:
        raw = checked_frame_samples(raw, identity, revision, measurement.get("native_pid"), platform)
        if aggregation != "p99":
            raise EvidenceError("Frame intervals require an explicit per-iteration p99 reduction")
        value = percentile(raw, 0.99)
    if value != finite_number(measurement.get("value"), "timing value", positive=True):
        raise EvidenceError("Declared timing value does not match the raw native metric export")
    if scenario == "startup" and measurement.get("native_pid") is not None:
        raise EvidenceError("A native PID is required for frame packets, not an XCTest launch metric")
    if platform == "ios":
        expected = "native-samples" if scenario != "startup" else "metrics"
        if sum(Path(match["path"]).name.endswith(expected + ".json") and match["kind"] == "xcode-metric-json"
               and match["role"] == "timing" for match in matches) != 1:
            raise EvidenceError(f"iOS {scenario} requires its identity-bound {expected}.json; firstDisplay is not a duration")
        if scenario == "startup" and any(Path(match["path"]).name.endswith("native-samples.json") for match in matches):
            raise EvidenceError("A CADisplayLink array cannot supply an iOS startup scalar")
    return [{
        "variant": variant, "scenario": scenario, "iteration": iteration, "metric": metric, "value": value,
        "definition": definition, "aggregation": aggregation, "source_samples": raw if scenario != "startup" else None,
        "artifacts": sorted(referenced),
    }]


def validate_resources(measurements: Any, artifacts: list[dict[str, Any]], platform: str) -> list[dict[str, Any]]:
    if not isinstance(measurements, list):
        raise EvidenceError("Resource measurements must be an array")
    output = []
    seen = set()
    for entry in measurements:
        if (not isinstance(entry, dict) or entry.get("platform") != platform
                or set(entry) != {"platform", "variant", "scenario", "iteration", "metric", "bytes", "native_pid",
                                  "artifacts"}):
            raise EvidenceError("Resource measurement has the wrong platform or an incomplete schema 2 identity")
        identity = (entry.get("variant"), entry.get("scenario"),
                    checked_iteration(entry.get("iteration"), "Resource iteration"), entry.get("metric"))
        if identity[0] not in VARIANTS or identity[1] not in SCENARIOS:
            raise EvidenceError("Resource measurement identity is invalid")
        if identity in seen:
            raise EvidenceError("Duplicate resource measurement")
        seen.add(identity)
        if identity[3] not in RESOURCE_METRICS:
            raise EvidenceError("Unsupported resource metric")
        value = entry.get("bytes")
        if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
            raise EvidenceError("Memory and binary size require positive integer bytes")
        pid = entry.get("native_pid")
        if identity[3] == "residentMemoryBytes" and (type(pid) is not int or pid <= 0):
            raise EvidenceError("Resident memory requires its observed native process identity")
        if identity[3] == "installedBinaryBytes" and pid is not None:
            raise EvidenceError("Installed binary size is a build product, not a process measurement")
        paths = entry.get("artifacts")
        if not isinstance(paths, list) or not paths or len(set(paths)) != len(paths):
            raise EvidenceError("Resource measurement requires unique native artifact references")
        for path in paths:
            if not isinstance(path, str):
                raise EvidenceError("Resource artifact paths must be strings")
            matches = [artifact for artifact in artifacts if artifact["path"] == path]
            expected_role = "memory" if identity[3] == "residentMemoryBytes" else "binary"
            if (len(matches) != 1 or (matches[0]["variant"], matches[0]["scenario"], matches[0]["iteration"]) != identity[:3]
                    or matches[0]["role"] != expected_role):
                raise EvidenceError("Resource measurement has mismatched native provenance")
            raw_value = checked_resource_value(matches[0], identity[3], matches[0]["source_revision"], pid)
            if raw_value != value:
                raise EvidenceError("Declared resource bytes do not match the native resource export")
        output.append({"variant": identity[0], "scenario": identity[1], "iteration": identity[2],
                       "metric": identity[3], "bytes": value, "artifacts": sorted(paths),
                       "source_revision": matches[0]["source_revision"],
                       "build_provenance_sha256": matches[0]["build_provenance_sha256"]})
    return output


def resource_pairs(resources: list[dict[str, Any]], environment: dict[str, Any]) -> list[dict[str, Any]]:
    pairs = []
    for scenario in ("scroll", "stateUpdate"):
        for iteration in ITERATIONS:
            memory = [resource for resource in resources if resource["metric"] == "residentMemoryBytes"
                      and resource["scenario"] == scenario and resource["iteration"] == iteration]
            reference = [resource for resource in memory if resource["variant"] == "reference"]
            generated = [resource for resource in memory if resource["variant"] == "generated"]
            if len(reference) != 1 or len(generated) != 1:
                raise EvidenceError(f"Missing resident memory pair: {scenario}.{iteration}")
            pairs.append({"scenario": scenario, "iteration": iteration, "metric": "residentMemoryBytes",
                          "unit": "bytes", "reference": reference[0]["bytes"], "generated": generated[0]["bytes"],
                          "delta": generated[0]["bytes"] - reference[0]["bytes"]})
    binaries = [resource for resource in resources if resource["metric"] == "installedBinaryBytes"]
    if len(binaries) != 2:
        raise EvidenceError("Need exactly one generated and one reference installed binary measurement")
    for variant in VARIANTS:
        matching = [resource for resource in binaries if resource["variant"] == variant]
        if len(matching) != 1:
            raise EvidenceError(f"Missing installed binary pair for {variant}")
    if binaries[0]["scenario"] != binaries[1]["scenario"]:
        raise EvidenceError("Installed binary pair must belong to one scenario")
    if binaries[0]["iteration"] != binaries[1]["iteration"]:
        raise EvidenceError("Installed binary pair must reference the same iteration's build identity")
    if any((resource["source_revision"], resource["build_provenance_sha256"]) !=
           (environment["source_revision"], environment["build_provenance"]["sha256"]) for resource in resources):
        raise EvidenceError("Resources cannot be backfilled from another source revision or build")
    binaries.sort(key=lambda resource: resource["variant"])
    pairs.append({"scenario": binaries[0]["scenario"], "iteration": None, "metric": "installedBinaryBytes",
                  "unit": "bytes", "reference": next(r["bytes"] for r in binaries if r["variant"] == "reference"),
                  "generated": next(r["bytes"] for r in binaries if r["variant"] == "generated")})
    pairs[-1]["delta"] = pairs[-1]["generated"] - pairs[-1]["reference"]
    return pairs


def make_report(manifest: Any, root: Path) -> dict[str, Any]:
    if not isinstance(manifest, dict) or manifest.get("schema") != 2:
        raise EvidenceError("Unsupported evidence schema: schema 2 requires explicit native scalar definitions")
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
        artifact, path = artifact_entry(entry, root, platform, environment)
        if path in paths:
            raise EvidenceError("Duplicate native artifact")
        paths.add(path)
        artifacts.append(artifact)
    build_path = environment["build_provenance"]["path"]
    if build_path not in paths:
        raise EvidenceError("Build provenance must be a checksummed raw artifact")
    build_artifact = next(artifact for artifact in artifacts if artifact["path"] == build_path)
    if build_artifact["sha256"] != environment["build_provenance"]["sha256"]:
        raise EvidenceError("Build provenance identity does not match its artifact bytes")
    if build_artifact["role"] != "build-provenance":
        raise EvidenceError("Build provenance path must have the build-provenance role")
    checked_build_provenance(build_artifact, environment, root)
    measurements = manifest.get("measurements")
    if not isinstance(measurements, list) or not measurements:
        raise EvidenceError("No raw measurements")
    samples = []
    for measurement in measurements:
        if not isinstance(measurement, dict) or measurement.get("platform") != platform:
            raise EvidenceError("Measurement platform disagrees with environment")
        samples.extend(samples_for(measurement, artifacts))
    resources = validate_resources(manifest.get("resources"), artifacts, platform)
    paired_resources = resource_pairs(resources, environment)
    comparisons = []
    for scenario in SCENARIOS:
        metric = SCENARIO_METRICS[platform][scenario]
        for iteration in ITERATIONS:
            for variant in VARIANTS:
                matching = [sample for sample in samples if sample["scenario"] == scenario
                            and sample["metric"] == metric and sample["iteration"] == iteration
                            and sample["variant"] == variant]
                if len(matching) != 1:
                    raise EvidenceError(f"Missing or duplicate raw sample: {variant}.{scenario}.{metric}.iteration{iteration}")
                trace_kind = {"ios": "xctrace", "harmonyos": "vendor-trace"}[platform]
                traces = [artifact for artifact in artifacts if artifact["scenario"] == scenario
                          and artifact["variant"] == variant and artifact["iteration"] == iteration
                          and artifact["role"] == "profiler" and artifact["kind"] == trace_kind]
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
        comparisons.append({"scenario": scenario, "metric": metric, "unit": "ms", "iterations": list(ITERATIONS), **quantiles})
    return {
        "schema": 2,
        "platform": platform,
        "target_label": environment["target_label"],
        "device_result": environment["device_result"],
        "physical_device_gate_satisfied": environment["device_result"],
        "environment": environment,
        "artifact_integrity": "verified",
        "threshold": {"relative_percent": 5.0, "absolute_ms": 0.1, "conjunction": "AND"},
        "comparisons": comparisons,
        "samples": samples,
        "resources": resources,
        "resource_pairs": paired_resources,
        "status": "fail" if any(row["p50"]["regressed"] or row["p99"]["regressed"] for row in comparisons) else "pass",
    }


def artifact_entry(entry: Any, root: Path, platform: str, environment: dict[str, Any]) -> tuple[dict[str, Any], str]:
    result, path = artifact(entry, root, platform, environment)
    return result, path


def markdown(report: dict[str, Any]) -> str:
    label = report["target_label"]
    lines = [
        f"# {report['platform'].upper()} paired benchmark report",
        "",
        f"**{label} RESULTS — {'physical-device evidence' if report['device_result'] else 'not device results'}.**",
        "The physical-device gate remains open. Do not extrapolate to another OS or target.",
        "",
        "Lower-is-better screening: greater than 5% AND greater than 0.1 ms at p50 or p99. "
        "Exact iteration identities 2...30 use nearest rank; native artifacts are checksummed.",
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
    lines += ["", "| Resource | Scenario | Iterations | Reference bytes | Generated bytes | Δ bytes |",
              "| --- | --- | --- | ---: | ---: | ---: |"]
    for row in report["resource_pairs"]:
        if row["metric"] == "installedBinaryBytes":
            lines.append(f"| {row['metric']} | {row['scenario']} | build pair | {row['reference']} | "
                         f"{row['generated']} | {row['delta']:+d} |")
        else:
            lines.append(f"| {row['metric']} | {row['scenario']} | {row['iteration']} | {row['reference']} | "
                         f"{row['generated']} | {row['delta']:+d} |")
    lines += ["", f"**Result: {report['status'].upper()}**", ""]
    return "\n".join(lines)
