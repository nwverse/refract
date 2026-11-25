#!/usr/bin/env python3
"""Recompute the canonical iOS build identity from original retained products."""

from __future__ import annotations

import hashlib
import os
import plistlib
import re
import stat
from pathlib import Path

MAX_EVIDENCE_FILE_BYTES = 64 * 1024 * 1024
BUNDLE_NAMES = ("RefractBench.app", "RefractBenchUITests-Runner.app",
                "RefractBenchUITests-Runner.app/PlugIns/RefractBenchUITests.xctest")


class BuildProvenanceError(ValueError):
    pass


def bounded_regular_file(path: Path) -> os.stat_result:
    path = path.absolute()
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode):
        raise BuildProvenanceError(f"Expected a bounded ordinary file, not a link, directory or special file: {path.name}")
    if metadata.st_size > MAX_EVIDENCE_FILE_BYTES:
        raise BuildProvenanceError(
            f"Evidence file exceeds the {MAX_EVIDENCE_FILE_BYTES}-byte bound: {path.name}")
    return metadata


def bounded_file_bytes(path: Path) -> bytes:
    bounded_regular_file(path)
    with path.open("rb") as stream:
        data = stream.read(MAX_EVIDENCE_FILE_BYTES + 1)
    if len(data) > MAX_EVIDENCE_FILE_BYTES:
        raise BuildProvenanceError(f"Evidence file exceeds the {MAX_EVIDENCE_FILE_BYTES}-byte bound: {path.name}")
    return data


def file_sha256(path: Path) -> str:
    bounded_regular_file(path)
    digest = hashlib.sha256()
    for offset in range(0, len(data := bounded_file_bytes(path)), 1024 * 1024):
        digest.update(data[offset:offset + 1024 * 1024])
    return digest.hexdigest()


def bundle_identity(products: Path, relative: str) -> dict:
    bundle = products / relative
    if not bundle.is_dir() or bundle.is_symlink():
        raise BuildProvenanceError(f"Build product is not a real bundle directory: {relative}")
    files = []
    directories = []
    for directory, directory_names, file_names in os.walk(bundle, topdown=True, followlinks=False):
        directory_names.sort()
        file_names.sort()
        for name in (*directory_names, *file_names):
            path = Path(directory) / name
            mode = path.lstat().st_mode
            if not stat.S_ISDIR(mode) and not stat.S_ISREG(mode):
                raise BuildProvenanceError(f"Build product contains a symbolic link or special file: {relative}")
    for directory, directory_names, file_names in os.walk(bundle, followlinks=False):
        directory_names.sort()
        directories.extend((Path(directory) / name).relative_to(products).as_posix()
                           for name in sorted(directory_names))
        for name in sorted(file_names):
            path = Path(directory) / name
            files.append({"path": path.relative_to(products).as_posix(),
                          "bytes": path.stat(follow_symlinks=False).st_size,
                          "executable": bool(path.stat(follow_symlinks=False).st_mode & 0o111),
                          "sha256": file_sha256(path)})
    if not files:
        raise BuildProvenanceError(f"Build product bundle has no files: {relative}")
    try:
        executable = plistlib.loads(bounded_file_bytes(bundle / "Info.plist")).get("CFBundleExecutable")
    except (OSError, plistlib.InvalidFileException) as error:
        raise BuildProvenanceError(f"Build product bundle Info.plist is missing or invalid: {relative}") from error
    expected_executable = f"{relative}/{executable}" if isinstance(executable, str) and executable else ""
    if not any(item["path"] == expected_executable for item in files):
        raise BuildProvenanceError(f"Build product CFBundleExecutable is missing from its identity: {relative}")
    return {"directories": sorted(directories), "files": files}


def generated_test_runs(derived_data: Path) -> list[Path]:
    sources = sorted(path for path in (derived_data / "Build/Products").glob("*.xctestrun")
                     if path.name != "iteration-trace-config.xctestrun"
                     and not path.name.startswith("iteration-trace-config-"))
    if len(sources) != 1 or sources[0].is_symlink():
        raise BuildProvenanceError("Exactly one original generated xctestrun file is required")
    bounded_regular_file(sources[0])
    return sources


def original_build_provenance(derived_data: Path, revision: str, *, checked_file_bytes=bounded_file_bytes) -> dict:
    """Recompute the canonical identity without writing or trusting a manifest."""
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Build provenance requires a committed 40-character source revision")
    products = derived_data / "Build/Products/Release-iphonesimulator"
    sources = sorted(path for path in (derived_data / "Build/Products").glob("*.xctestrun")
                     if path.name != "iteration-trace-config.xctestrun"
                     and not path.name.startswith("iteration-trace-config-"))
    if len(sources) != 1 or sources[0].is_symlink():
        raise ValueError("Exactly one original generated xctestrun file is required")
    bounded_regular_file(sources[0])
    digest = hashlib.sha256()
    for offset in range(0, len(data := checked_file_bytes(sources[0])), 1024 * 1024):
        digest.update(data[offset:offset + 1024 * 1024])
    return {"schema": 1, "source_revision": revision, "configuration": "Release-iphonesimulator",
            "source_xctestrun": {"path": sources[0].name, "sha256": digest.hexdigest()},
            "products": {name: bundle_identity(products, name) for name in BUNDLE_NAMES}}
