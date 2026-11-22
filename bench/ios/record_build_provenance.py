#!/usr/bin/env python3
"""Record immutable source and app/test product identity after build-for-testing."""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from iteration_trace_runner import HandshakeError, record_build_provenance


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--derived-data", required=True, type=Path)
    parser.add_argument("--source-revision", required=True)
    args = parser.parse_args(argv)
    try:
        record_build_provenance(args.derived_data, args.source_revision)
    except (HandshakeError, OSError) as error:
        print(f"record-build-provenance: ERROR: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
