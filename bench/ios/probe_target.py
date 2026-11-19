#!/usr/bin/env python3
"""Read-only target classification; no lifecycle command is executed."""

import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    parser.add_argument("--simulators", required=True, type=Path)
    parser.add_argument("--targets", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    payload = json.loads(args.simulators.read_text(encoding="utf-8"))
    matches = [device for runtime, devices in payload.get("devices", {}).items()
               for device in devices if device.get("udid") == args.udid]
    if len(matches) != 1:
        raise SystemExit("The explicit target must be one available simulator; no target was created or booted.")
    device = matches[0]
    if device.get("state") != "Booted":
        raise SystemExit("The explicitly owned target must already be booted; this script will not boot it.")
    metadata = {"target_label": "SIMULATOR", "device_result": False,
                "model": device.get("deviceTypeIdentifier"), "state": device["state"]}
    if metadata["model"] is None:
        raise SystemExit("Simulator metadata lacks its explicit model identifier.")
    targets = json.loads(args.targets.read_text(encoding="utf-8"))
    target_matches = []
    def visit(value):
        if isinstance(value, dict):
            properties = value.get("deviceProperties", value)
            if properties.get("udid") == args.udid:
                target_matches.append(value)
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
    visit(targets)
    if len(target_matches) != 1:
        raise SystemExit("The explicit simulator UDID is not confirmed by devicectl; refusing an ambiguous target.")
    args.output.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
