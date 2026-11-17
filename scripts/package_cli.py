#!/usr/bin/env python3
"""Build a local, deterministic CLI archive from a clean source revision.

python3 scripts/package_cli.py --output <directory> [--revision HEAD]
python3 scripts/package_cli.py --output <directory> --verify-reproducible

This does not publish artifacts, install tools or download executable binaries.
Run it from the checkout, not from a build or extracted archive directory.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.1.0"
TOOLCHAIN = "6.4.2"
ARCHIVE_EPOCH = 0
SWIFT_FLAGS = ["--disable-automatic-resolution", "--configuration", "release", "--product", "refract", "--jobs", "4",
               "--static-swift-stdlib"]


def run(command: list[str], *, cwd: Path = ROOT, stdout=None) -> str:
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=stdout is None, stdout=stdout, check=False)
    if result.returncode != 0:
        diagnostic = (result.stderr or "").strip() if stdout is None else f"exit status {result.returncode}"
        raise RuntimeError(f"{command[0]} failed: {diagnostic}")
    return result.stdout.strip() if stdout is None else ""


def revision() -> str:
    value = run(["git", "rev-parse", "HEAD"])
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        raise ValueError("git returned an invalid source revision")
    return value


def validate_revision(value: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        raise ValueError("--revision must be a full, resolved 40-character commit; avoid ambiguous refs")
    if run(["git", "cat-file", "-t", value]) != "commit":
        raise ValueError("--revision is not a commit")
    return value


def load_notices() -> tuple[dict[str, dict[str, str]], bytes]:
    path = ROOT / "scripts" / "release" / "third_party_notices.json"
    document = json.loads(path.read_text(encoding="utf-8"))
    expected_pins = set()
    for pin in json.loads((ROOT / "Package.resolved").read_text(encoding="utf-8"))["pins"]:
        identity = pin["identity"]
        expected_pins.add(identity)
        notice = document.get(identity)
        if not notice or pin["state"]["revision"] != notice["revision"]:
            raise ValueError(f"missing or stale third-party notice for {identity}")
        archive = ROOT / notice["licenseFile"]
        actual = hashlib.sha256(archive.read_bytes()).hexdigest()
        if actual != notice["sha256"]:
            raise ValueError(f"third-party license digest does not match {identity}")
    if set(document) != expected_pins:
        raise ValueError("third-party notices must exactly cover the locked source dependencies")
    notices = [
        "Third-party source dependencies for the Refract CLI",
        "",
        "The dependency is compiled into the host CLI; it is not added to generated applications.",
        "A source build uses Package.resolved; these notices accompany the corresponding local binary package.",
        "",
    ]
    for name, notice in sorted(document.items()):
        license_bytes = (ROOT / notice["licenseFile"]).read_bytes()
        notices.extend([
            f"Component: {name}",
            f"Source: {notice['url']}",
            f"Version: {notice['version']}",
            f"Revision: {notice['revision']}",
            f"License: {notice['license']}",
            f"License archive: {notice['licenseFile']}",
            f"License SHA-256: {notice['sha256']}",
            "",
            license_bytes.decode("utf-8"),
            "",
        ])
    return document, "\n".join(notices).encode("utf-8")


def host_target() -> tuple[str, str, str]:
    systems = {"Linux": "linux", "Darwin": "macos"}
    machines = {"x86_64": "x86_64", "AMD64": "x86_64", "arm64": "arm64", "aarch64": "arm64"}
    if platform.system() not in systems or platform.machine() not in machines:
        raise ValueError(f"unsupported host: {platform.system()} {platform.machine()}")
    os_name, architecture = systems[platform.system()], machines[platform.machine()]
    triple = f"{architecture}-apple-macosx" if os_name == "macos" else f"{architecture}-unknown-linux-gnu"
    return os_name, architecture, triple


def check_tools(triple: str) -> dict[str, object]:
    swift = shutil.which("swift")
    git = shutil.which("git")
    if not swift or not git or not shutil.which("strip"):
        raise ValueError("Swift, git and strip must be installed and discoverable on PATH")
    if os.environ.get("REFRACT_SWIFT_TOOLCHAIN") and os.environ["REFRACT_SWIFT_TOOLCHAIN"] != TOOLCHAIN:
        raise ValueError(f"this release contract requires Swift {TOOLCHAIN}")
    selected = run(["swift", "--version"])
    if not selected.startswith(f"Apple Swift version {TOOLCHAIN} ") and not selected.startswith(f"Swift version {TOOLCHAIN} "):
        raise ValueError(f"Swift {TOOLCHAIN} is required; `swift --version` returned: {selected.splitlines()[0]}")
    return {"swiftVersion": TOOLCHAIN, "hostTriple": triple, "buildConfiguration": "release",
            "buildOptions": [flag for flag in SWIFT_FLAGS[1:] if flag != "--static-swift-stdlib" or host_target()[0] == "linux"],
            "staticSwiftRuntime": host_target()[0] == "linux"}


def source_files(commit: str) -> list[str]:
    names = run(["git", "ls-tree", "-r", "-z", "--name-only", commit]).split("\0")
    return sorted(name for name in names if name)


def version_source(original: bytes, commit: str) -> bytes:
    text = original.decode("utf-8")
    text, count = re.subn(r'(?m)^(\s*static let sourceRevision = )"[^"]*"$',
                          rf'\1"{commit}"', text)
    if count != 1:
        raise ValueError("could not stamp exactly one CLI source revision")
    return text.encode("utf-8")


def source_archive(commit: str, destination: Path) -> None:
    validate_revision(commit)
    entries = []
    version_path = "Sources/RefractCLI/Version.swift"
    if version_path not in source_files(commit):
        raise ValueError("source revision does not contain the CLI version file")
    for name in source_files(commit):
        entry = run(["git", "ls-tree", "-z", commit, "--", name]).split("\0")[0]
        metadata, object_name = entry.split("\t", 1)
        mode_text, object_type, _ = metadata.split()
        if object_type != "blob" or mode_text not in {"100644", "100755"}:
            raise ValueError(f"source archive cannot contain non-regular entry: {object_name}")
        data = run_bytes(["git", "show", f"{commit}:{name}"])
        entries.append((name, 0o755 if mode_text == "100755" else 0o644,
                        version_source(data, commit) if name == version_path else data))
    archive_bytes = deterministic_tar(f"refract-source-{VERSION}", entries)
    destination.write_bytes(gzip.compress(archive_bytes, compresslevel=9, mtime=ARCHIVE_EPOCH))


def run_bytes(command: list[str], cwd: Path = ROOT) -> bytes:
    result = subprocess.run(command, cwd=cwd, capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode("utf-8", "replace").strip())
    return result.stdout


def extract_archive(archive: Path, destination: Path) -> None:
    """Validate our canonical archive before extraction on stock Python 3.11 as well as newer releases."""
    with tarfile.open(archive, "r:gz") as package:
        members = package.getmembers()
        if not members:
            raise ValueError("archive is empty")
        root = members[0].name.rstrip("/")
        for member in members:
            path = PurePosixPath(member.name)
            if (not member.name.startswith(root + "/") and member.name != root) or path.is_absolute() or ".." in path.parts:
                raise ValueError("archive contains an unsafe path outside its root")
            if not (member.isfile() or member.isdir()):
                raise ValueError("archive may contain only regular files and directories")
            if member.mode & ~(stat.S_IRWXU | stat.S_IRWXG | stat.S_IRWXO):
                raise ValueError("archive contains special permission bits")
            if member.isfile() and not package.extractfile(member):
                raise ValueError("archive contains an unreadable file")
        package.extractall(destination)


def deterministic_tar(prefix: str, entries: list[tuple[str, int, bytes]]) -> bytes:
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        directories = {prefix}
        for name, _, _ in entries:
            parent = PurePosixPath(name).parent
            while str(parent) != ".":
                directories.add(f"{prefix}/{parent}")
                parent = parent.parent
        for directory in sorted(directories):
            info = tarfile.TarInfo(directory)
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            apply_metadata(info)
            archive.addfile(info)
        for name, mode, data in sorted(entries):
            info = tarfile.TarInfo(f"{prefix}/{name}")
            info.size = len(data)
            info.mode = mode
            apply_metadata(info)
            archive.addfile(info, io.BytesIO(data))
    return output.getvalue()


def apply_metadata(info: tarfile.TarInfo) -> None:
    info.mtime = ARCHIVE_EPOCH
    info.uid = info.gid = 0
    info.uname = info.gname = ""


def build(source: Path, scratch: Path) -> Path:
    run(["swift", "build", "--package-path", str(source), "--scratch-path", str(scratch), *SWIFT_FLAGS], stdout=sys.stderr)
    binary = run(["swift", "build", "--package-path", str(source), "--scratch-path", str(scratch), *SWIFT_FLAGS, "--show-bin-path"])
    products = Path(binary)
    executable = products / "refract"
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError("SwiftPM did not produce an executable refract product")
    run(["strip", "--strip-debug", str(executable)])
    bundle = products / "refract_RefractMapping.bundle"
    schema = bundle / "refract.schema.json"
    if not schema.is_file():
        raise ValueError("SwiftPM did not produce the required mapping resource bundle")
    return products


def binary_entries(products: Path, commit: str, metadata: dict[str, object], notices: bytes) -> list[tuple[str, int, bytes]]:
    resource = (products / "refract_RefractMapping.bundle/refract.schema.json").read_bytes()
    expected = run_bytes(["git", "show", f"{commit}:Sources/RefractMapping/Resources/refract.schema.json"])
    if resource != expected:
        raise ValueError("packaged mapping schema differs from the source revision")
    entries = [
        ("bin/refract", 0o755, (products / "refract").read_bytes()),
        ("LICENSE", 0o644, (ROOT / "LICENSE").read_bytes()),
        ("THIRD-PARTY-NOTICES.txt", 0o644, notices),
        ("BUILD-INFO.json", 0o644, json.dumps({
            "formatVersion": 1,
            "packageVersion": VERSION,
            "sourceRevision": commit,
            **metadata,
            "runtimeDependencyPolicy": "The native CLI statically links its Swift runtime; generated apps have no Refract runtime dependency. System library requirements still apply.",
            "portability": "Native host binary only; OS, CPU, toolchain and runtime requirements apply. No cross-platform equivalence is claimed.",
        }, indent=2, sort_keys=True).encode("utf-8") + b"\n"),
    ]
    for name in ("Package.swift", "Package.resolved"):
        entries.append((f"source/{name}", 0o644, run_bytes(["git", "show", f"{commit}:{name}"])))
    bundle = products / "refract_RefractMapping.bundle"
    for path in sorted(bundle.rglob("*")):
        if path.is_symlink() or (path.is_file() and not stat.S_ISREG(path.stat().st_mode)):
            raise ValueError("resource bundle contains a symlink or non-regular file")
        if path.is_file():
            relative = path.relative_to(products).as_posix()
            entries.append((f"lib/{relative}", 0o755 if os.access(path, os.X_OK) else 0o644, path.read_bytes()))
    return entries


def validate_package(archive: Path, parent: Path, commit: str) -> None:
    root = f"refract-{VERSION}-{host_target()[0]}-{host_target()[1]}"
    extract_archive(archive, parent)
    extracted = parent / root
    executable = extracted / "bin" / "refract"
    # These tests created the package: only restore the known regular executable bit.
    executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
    output = run([str(executable), "--version"])
    info = json.loads((extracted / "BUILD-INFO.json").read_text(encoding="utf-8"))
    if output != f"refract {VERSION} ({info['sourceRevision']})":
        raise ValueError(f"packaged CLI version mismatch: {output}")
    with tempfile.TemporaryDirectory(prefix="refract-package-smoke.", dir=parent) as directory:
        smoke = Path(directory)
        (smoke / "Input.swift").write_text(
            'import SwiftUI\nstruct Smoke: View { var body: some View { Text(verbatim: "Packaged") } }\n',
            encoding="utf-8")
        run([str(executable), "generate", "--input", str(smoke / "Input.swift"),
             "--android-out", str(smoke / "android"), "--harmony-out", str(smoke / "harmony")])
        kotlin = smoke / "android/Input.kt"
        arkts = smoke / "harmony/Input.ets"
        if not kotlin.is_file() or not arkts.is_file():
            raise ValueError("packaged CLI did not generate both native outputs")
        if "Packaged" not in kotlin.read_text(encoding="utf-8") or "Packaged" not in arkts.read_text(encoding="utf-8"):
            raise ValueError("packaged CLI generated incomplete native output")
        resource = extracted / "lib/refract_RefractMapping.bundle/refract.schema.json"
        if not resource.is_file():
            raise ValueError("installed package is missing its mapping schema")
        if resource.read_bytes() != run_bytes(["git", "show", f"{commit}:Sources/RefractMapping/Resources/refract.schema.json"]):
            raise ValueError("installed mapping schema differs from the source revision")


def package_once(commit: str, destination: Path, os_name: str, architecture: str,
                 metadata: dict[str, object], notices: bytes, scratch: Path) -> Path:
    scratch.mkdir()
    source_tar = scratch / "source.tar.gz"
    source_archive(commit, source_tar)
    source = scratch / "source"
    source.mkdir()
    source_root = source / f"refract-source-{VERSION}"
    extract_archive(source_tar, source)
    products = build(source_root, scratch / "swift-build")
    archive = destination / f"refract-{VERSION}-{os_name}-{architecture}.tar.gz"
    entries = binary_entries(products, commit, metadata, notices)
    archive.write_bytes(gzip.compress(deterministic_tar(f"refract-{VERSION}-{os_name}-{architecture}", entries),
                                       compresslevel=9, mtime=ARCHIVE_EPOCH))
    installed = scratch / "installed"
    installed.mkdir()
    validate_package(archive, installed, commit)
    return archive


def create_package(commit: str, output: Path, reproducible: bool) -> Path:
    os_name, architecture, triple = host_target()
    metadata = check_tools(triple)
    _, notices = load_notices()
    if output.exists():
        if not output.is_dir() or any(output.iterdir()):
            raise ValueError("--output must be a new or empty directory")
    else:
        output.mkdir(parents=True)
    temporary_root = Path(os.environ["REFRACT_PACKAGE_TEMP"]) if os.environ.get("REFRACT_PACKAGE_TEMP") else None
    if temporary_root:
        if temporary_root.exists() and not temporary_root.is_dir():
            raise ValueError("REFRACT_PACKAGE_TEMP must name a directory outside the source checkout")
        if temporary_root.resolve() == ROOT or ROOT in temporary_root.resolve().parents:
            raise ValueError("REFRACT_PACKAGE_TEMP must be outside the source checkout")
        temporary_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="refract-cli-package.", dir=temporary_root) as temporary:
        scratch = Path(temporary)
        first = package_once(commit, output, os_name, architecture, metadata, notices, scratch / "first")
        if reproducible:
            second = package_once(commit, output, os_name, architecture, metadata, notices, scratch / "second")
            if first.read_bytes() != second.read_bytes():
                raise ValueError("two clean builds differ; do not distribute this archive as reproducible")
        checksum = hashlib.sha256(first.read_bytes()).hexdigest()
        checksum_path = first.with_suffix(first.suffix + ".sha256")
        checksum_path.write_text(f"{checksum}  {first.name}\n", encoding="ascii")
        source = output / f"refract-source-{VERSION}-{commit}.tar.gz"
        source_bytes = (scratch / "first/source.tar.gz").read_bytes()
        source.write_bytes(source_bytes)
        source_checksum = hashlib.sha256(source_bytes).hexdigest()
        source.with_suffix(source.suffix + ".sha256").write_text(f"{source_checksum}  {source.name}\n", encoding="ascii")
        verification = run(["sha256sum", "--check", "--strict", checksum_path.name, source.with_suffix(source.suffix + ".sha256").name], cwd=output) if shutil.which("sha256sum") else ""
        if verification:
            print(verification)
        print(f"Created and smoke-tested {first}")
        print(f"SHA-256: {checksum}")
        print(f"Clean source archive: {source}")
        if reproducible:
            print("Reproducibility: two independent clean builds produced byte-identical archives on this host toolchain")
        return first


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="artifact directory, outside the source checkout")
    parser.add_argument("--revision", default="HEAD", help="full commit to package; default: current HEAD")
    parser.add_argument("--verify-reproducible", action="store_true", help="build twice and compare complete archives")
    arguments = parser.parse_args()
    try:
        commit = revision() if arguments.revision == "HEAD" else validate_revision(arguments.revision)
        output = arguments.output.resolve()
        if output == ROOT or ROOT in output.parents:
            raise ValueError("--output must be outside the repository checkout")
        if output.exists() and any(output.iterdir()):
            raise ValueError("--output must be a new or empty directory")
        create_package(commit, output, arguments.verify_reproducible)
    except (OSError, ValueError, RuntimeError, KeyError, json.JSONDecodeError, tarfile.TarError) as error:
        print(f"package_cli: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
