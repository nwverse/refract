#!/usr/bin/env python3
"""Run the selected committed-draft native case; never claim Chinese IME evidence.

The caller must provide an authorized toolchain, signed HAPs and an explicitly
allocated target. UI Test inputText is committed-text injection, not preedit,
candidate selection, keyboard-window or IME verification.
"""
from __future__ import annotations

import importlib.util
import json
from datetime import datetime, timezone
import os
import shutil
import subprocess
import sys
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().with_name("verify_harmony_settings.py")
SPEC = importlib.util.spec_from_file_location("refract_harmony_evidence", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
SETTINGS = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = SETTINGS
with mock.patch.object(sys, "path", [str(SCRIPT.parent), *sys.path]):
    SPEC.loader.exec_module(SETTINGS)

SELECTED_CASE = ("GeneratedComposer", "committed_draft_focus_done_and_recreation")


def validate_result(output: str) -> dict[str, object]:
    """Accept only the observed composer case, never a settings success."""
    return SETTINGS.validate_result(output, (SELECTED_CASE,))


def main(argv: list[str] | None = None) -> int:
    args = SETTINGS.parse_arguments(list(sys.argv[1:] if argv is None else argv))
    if not SETTINGS.ARGUMENT.fullmatch(args.target):
        print("target must be a serial without whitespace or shell metacharacters", file=sys.stderr)
        return 2
    output = Path(args.output)
    if output.exists():
        print("verification output must be a new directory; refusing to mix evidence", file=sys.stderr)
        return 2
    output.mkdir(parents=True)
    log_path = output / "commands.log"
    metadata: dict[str, object] = {
        "status": "incomplete",
        "imeVerified": False,
        "renderVerified": False,
        "performanceMeasured": False,
        "buildProvenance": "both installed HAPs must match the outputs of this run's native builds",
        "evidenceScope": "native committed-draft UI Test injection; no Chinese IME or candidate evidence",
        "targetClass": args.target_class,
        "targetDescription": args.target_description,
        "startedUtc": datetime.now(timezone.utc).isoformat(),
    }
    try:
        metadata["sourceRevision"] = SETTINGS.source_revision()
        tools, errors = SETTINGS.PREFLIGHT.preflight(os.environ)
        if errors:
            raise SETTINGS.VerificationError("; ".join(errors))
        if not shutil.which("hdc"):
            raise SETTINGS.VerificationError("authorized hdc executable was not found on PATH")
        metadata["toolchainVersion"] = SETTINGS.tool_version(tools, log_path)
        with SETTINGS.package_snapshots() as snapshot_paths:
            metadata["nativePackages"] = SETTINGS.native_packages(
                tools, log_path, snapshot_paths["app"].parent
            )
            selected = {
                role: args.app_hap if role == "app" and args.app_hap is not None else built
                for role, built in SETTINGS.PACKAGE_OUTPUTS.items()
            }
            if args.test_hap is not None:
                selected["test"] = args.test_hap
            hdc = ["hdc", "-t", args.target]
            for role in selected:
                # Revalidate every selected input, then install only this run's
                # private snapshot rather than reopening a mutable caller path.
                metadata["nativePackages"] = SETTINGS.package_provenance(selected, snapshot_paths)
                install = SETTINGS.package_provenance(selected, snapshot_paths)["artifacts"][role]["installSnapshotPath"]
                SETTINGS.execute([*hdc, "install", str(install)], log_path)
            result = SETTINGS.execute(
                SETTINGS.selected_suite_command(hdc, SELECTED_CASE[0]), log_path, timeout=180
            )
        metadata["nativeTests"] = validate_result(result.stdout)
        metadata["status"] = "native-committed-draft-executed-ime-unverified"
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError,
            SETTINGS.VerificationError, json.JSONDecodeError) as error:
        metadata["status"] = "failed-or-blocked"
        metadata["blocker"] = str(error)
        print(f"harmony-composer: {error}", file=sys.stderr)
        return 1
    finally:
        metadata["finishedUtc"] = datetime.now(timezone.utc).isoformat()
        (output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        print("NO CHINESE PREEDIT, CANDIDATE, KEYBOARD-WINDOW OR IME VERIFICATION IS CLAIMED")


if __name__ == "__main__":
    sys.exit(main())
