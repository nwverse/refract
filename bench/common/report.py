#!/usr/bin/env python3
"""Validate one native paired evidence manifest and emit report.json/report.md."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from paired_report import EvidenceError, make_report, markdown


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"), parse_constant=lambda value: (_ for _ in ()).throw(
            EvidenceError(f"Non-finite JSON value: {value}")))
        report = make_report(manifest, args.manifest.parent)
        if args.output.exists() and any(args.output.iterdir()):
            raise EvidenceError("Refusing to overwrite an existing evidence directory")
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n",
                                                 encoding="utf-8")
        (args.output / "report.md").write_text(markdown(report), encoding="utf-8")
    except (OSError, UnicodeError, json.JSONDecodeError, EvidenceError, KeyError, TypeError) as error:
        print(f"paired-report: ERROR: {error}", file=sys.stderr)
        return 2
    print(markdown(report), end="")
    return 1 if report["status"] == "fail" else 0


if __name__ == "__main__":
    sys.exit(main())
