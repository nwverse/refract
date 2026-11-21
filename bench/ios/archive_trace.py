#!/usr/bin/env python3
"""Archive an already captured Instruments .trace package without replacing evidence.

This operates on local directories only. It does not run Instruments, select a
target, correlate iterations or establish that a package is performance evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


class ArchiveError(ValueError):
    pass


def archive_trace(source: Path, output: Path) -> tuple[int, str]:
    try:
        source_stat = source.lstat()
    except OSError as error:
        raise ArchiveError(f"Cannot inspect the trace package: {error}") from error
    if not stat.S_ISDIR(source_stat.st_mode) or source.is_symlink() or source.suffix != ".trace":
        raise ArchiveError("Source must be a real directory with the .trace suffix")
    if output.exists() or output.is_symlink():
        raise ArchiveError("Refusing to replace an existing output or symbolic link")
    if output.suffixes[-2:] != [".trace", ".zip"]:
        raise ArchiveError("Output must have the .trace.zip suffix")
    try:
        output.resolve().relative_to(source.resolve())
    except ValueError:
        pass
    else:
        raise ArchiveError("The trace package cannot contain its own archive")
    entries = []
    for directory, directory_names, file_names in os.walk(source, topdown=True, followlinks=False):
        parent = Path(directory)
        for name in sorted(directory_names):
            if not stat.S_ISDIR((parent / name).lstat().st_mode):
                raise ArchiveError("Trace package directories must be real directories, not links")
        for name in sorted(file_names):
            path = parent / name
            try:
                mode = path.lstat().st_mode
            except OSError as error:
                raise ArchiveError(f"Cannot inspect a package member: {error}") from error
            if not stat.S_ISREG(mode):
                raise ArchiveError("Trace packages may contain only ordinary files and directories; links are rejected")
            entries.append(path)
    if not entries:
        raise ArchiveError("An empty trace package is not native evidence")
    entries.sort(key=lambda path: path.relative_to(source).as_posix())

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        descriptor, name = tempfile.mkstemp(prefix=f".{output.name}.", suffix=".tmp", dir=output.parent)
        temporary = Path(name)
        with os.fdopen(descriptor, "w+b") as stream, zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in entries:
                relative = (PurePosixPath(source.name) / PurePosixPath(path.relative_to(source).as_posix())).as_posix()
                # Set a fixed timestamp for deterministic archival. Acquisition
                # time belongs in the separately retained native provenance.
                info = zipfile.ZipInfo(relative, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = (path.stat(follow_symlinks=False).st_mode & 0xFFFF) << 16
                info.create_system = 3
                with path.open("rb") as member:
                    archive.writestr(info, member.read())
        os.link(temporary, output)
    except (OSError, zipfile.BadZipFile, RuntimeError) as error:
        raise ArchiveError(f"Could not preserve the trace package: {error}") from error
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)

    digest = hashlib.sha256()
    with output.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return output.stat().st_size, digest.hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="An already captured .trace directory")
    parser.add_argument("--output", required=True, type=Path, help="A new .trace.zip file")
    args = parser.parse_args(argv)
    try:
        size, checksum = archive_trace(args.source, args.output)
    except (ArchiveError, OSError) as error:
        print(f"archive-trace: ERROR: {error}", file=sys.stderr)
        return 2
    print(f"path={args.output}\nbytes={size}\nsha256={checksum}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
