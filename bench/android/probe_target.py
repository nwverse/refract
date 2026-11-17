#!/usr/bin/env python3
"""Read-only emulator readiness probe, except for the documented storage write test.

This never creates, boots, stops, roots or reboots a target. A failed probe is a
blocker, not a benchmark result. The optional JSON file contains no serial or
host-specific paths.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

PROPERTIES = (
    "ro.product.model",
    "ro.product.device",
    "ro.build.version.release",
    "ro.build.version.sdk",
    "ro.build.display.id",
    "ro.build.type",
    "ro.product.cpu.abi",
    "ro.kernel.qemu",
    "sys.boot_completed",
    "ro.hardware.egl",
    "ro.hardware.vulkan",
    "ro.opengles.version",
    "qemu.gles",
    "debug.sf.hw",
)
SERVICES = ("package", "mount", "SurfaceFlinger")
OUTPUT_ROOT = "/sdcard/Android/media/dev.refract.bench.test"


class ProbeError(RuntimeError):
    pass


def select_target(listing: str, requested: str | None) -> str:
    targets = []
    for line in listing.splitlines()[1:]:
        fields = line.strip().split()
        if len(fields) >= 2:
            targets.append((fields[0], fields[1]))
    if requested:
        matches = [serial for serial, state in targets if serial == requested]
        if not matches:
            raise ProbeError("ANDROID_SERIAL is not attached; no target was started.")
        if dict(targets)[requested] != "device":
            raise ProbeError("The selected target is not in the device state.")
        return requested
    if len(targets) != 1:
        raise ProbeError("Attach exactly one target or set ANDROID_SERIAL; no target was started.")
    serial, state = targets[0]
    if state != "device":
        raise ProbeError("The attached target is not in the device state.")
    return serial


def inspect(properties: dict[str, str], volumes: str, source_revision: str) -> dict[str, Any]:
    if not re.fullmatch(r"[0-9a-f]{40}", source_revision):
        raise ProbeError("A full Git source revision is required.")
    if properties.get("sys.boot_completed") != "1":
        raise ProbeError("Android has not completed boot; the target was not restarted.")
    if properties.get("ro.kernel.qemu") != "1":
        raise ProbeError("This runner supports an explicitly identified emulator, not an unverified device label.")
    sdk = properties.get("ro.build.version.sdk", "")
    if not sdk.isdigit() or int(sdk) < 26:
        raise ProbeError("A stable API 26+ target is required.")
    mounted = any(
        line.strip().startswith("emulated;") and line.strip().endswith(" mounted")
        for line in volumes.splitlines()
    )
    if not mounted:
        raise ProbeError("External storage has no mounted emulated volume; no measurement was started.")
    for key in ("ro.product.model", "ro.product.device", "ro.build.display.id", "ro.build.type",
                "ro.product.cpu.abi"):
        if not properties.get(key):
            raise ProbeError(f"Required target property is unavailable: {key}")
    return {
        "status": "ready",
        "emulator": True,
        "device_result": False,
        "source": "read-only adb properties, service checks and a bounded storage write probe",
        "source_revision": source_revision,
        "target": {
            "model": properties["ro.product.model"],
            "device": properties["ro.product.device"],
            "os_release": properties["ro.build.version.release"],
            "sdk": int(sdk),
            "build_id": properties["ro.build.display.id"],
            "os_build_type": properties["ro.build.type"],
            "abi": properties["ro.product.cpu.abi"],
        },
        "rendering": {
            key: properties.get(key) or "unreported"
            for key in ("ro.hardware.egl", "ro.hardware.vulkan", "ro.opengles.version", "qemu.gles", "debug.sf.hw")
        },
        "services": {service: "available" for service in SERVICES},
        "storage": {"emulated_volume": "mounted", "output_writable": True},
        "benchmark_build_type": "release",
        "compilation_mode": "Partial",
        "macro_iterations": 10,
    }


class Adb:
    def __init__(self, executable: Path, timeout: float):
        self.executable = executable
        self.timeout = timeout

    def call(self, arguments: list[str], serial: str | None = None) -> str:
        command = [str(self.executable)]
        if serial:
            command += ["-s", serial]
        command += arguments
        try:
            completed = subprocess.run(
                command, capture_output=True, text=True, timeout=self.timeout, check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ProbeError(f"adb did not complete a bounded {arguments[0]} probe; no target was restarted.") from error
        if completed.returncode != 0:
            raise ProbeError(f"adb rejected the {arguments[0]} probe; no target was restarted.")
        return completed.stdout.strip().replace("\r", "")


def probe(adb: Adb, requested_serial: str | None, source_revision: str) -> dict[str, Any]:
    serial = select_target(adb.call(["devices"]), requested_serial)
    properties = {key: adb.call(["shell", "getprop", key], serial) for key in PROPERTIES}
    for service in SERVICES:
        response = adb.call(["shell", "service", "check", service], serial)
        if not response or "not found" in response.lower():
            raise ProbeError(f"Required Android service is unavailable: {service}")
    volumes = adb.call(["shell", "sm", "list-volumes", "all"], serial)
    result = inspect(properties, volumes, source_revision)
    # This is the only target write: create the documented output directory and
    # verify its writability. It does not alter existing files or mount state.
    adb.call(["shell", f"mkdir -p '{OUTPUT_ROOT}' && test -w '{OUTPUT_ROOT}'"], serial)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", type=Path, default=Path(os.environ.get("ANDROID_HOME", "")) / "platform-tools/adb")
    parser.add_argument("--serial", default=os.environ.get("ANDROID_SERIAL"))
    parser.add_argument("--timeout", type=float, default=15.0)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    if args.output.exists():
        parser.error("Refusing to overwrite an existing target probe; choose a new run directory.")
    try:
        if not math_is_finite_positive(args.timeout):
            raise ProbeError("The probe timeout must be finite and positive.")
        result = probe(Adb(args.adb, args.timeout), args.serial, args.source_revision)
        status = 0
    except ProbeError as error:
        result = {"status": "blocked", "device_result": False, "source_revision": args.source_revision,
                  "blocker": str(error)}
        print(f"target-probe: BLOCKED: {error}", file=sys.stderr)
        status = 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if status == 0:
        print("Target probe ready: EMULATOR (not a physical device).")
    return status


def math_is_finite_positive(value: float) -> bool:
    return math.isfinite(value) and value > 0


if __name__ == "__main__":
    sys.exit(main())
