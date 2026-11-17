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


def run(command: list[str], *, cwd: Path | None = None, stdout=None) -> str:
    result = subprocess.run(command, cwd=ROOT if cwd is None else cwd, text=True,
                            capture_output=stdout is None, stdout=stdout, check=False)
    if result.returncode != 0:
        diagnostic = (result.stderr or "").strip() if stdout is None else f"exit status {result.returncode}"
        raise RuntimeError(f"{command[0]} failed: {diagnostic}")
    return result.stdout.strip() if stdout is None else ""


def resource_bundle(products: Path) -> Path:
    bundle = products / "refract_RefractMapping.bundle"
    schemas = [path for path in bundle.rglob("refract.schema.json")
               if path.is_file() and not path.is_symlink()]
    if len(schemas) != 1 or any(path.is_symlink() for path in bundle.rglob("*")):
        raise ValueError("SwiftPM must produce one regular mapping schema in a symlink-free resource bundle")
    return schemas[0]


def swift_build_flags(os_name: str) -> list[str]:
    flags = list(SWIFT_FLAGS)
    # macOS provides the Swift runtime in the OS and its compiler rejects static Swift linkage.
    if os_name == "macos":
        flags.remove("--static-swift-stdlib")
    return flags


def strip_executable(executable: Path, os_name: str) -> None:
    # Apple strip uses -S for debugging symbols; GNU strip uses --strip-debug.
    run(["strip", "-S" if os_name == "macos" else "--strip-debug", str(executable)])


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


def committed_bytes(commit: str, path: str) -> bytes:
    """Read a required regular file from the selected commit, never the working tree."""
    relative = PurePosixPath(path)
    if relative.is_absolute() or ".." in relative.parts or relative != PurePosixPath(path.strip()):
        raise ValueError("provenance file must be a normalized repository-relative path")
    result = subprocess.run(["git", "cat-file", "-t", f"{commit}:{path}"], cwd=ROOT,
                            capture_output=True, text=True, check=False)
    if result.returncode != 0 or result.stdout.strip() != "blob":
        raise ValueError(f"selected revision {commit} lacks required packaging input {path}; "
                         "restore it as a regular file in that commit or select a complete revision")
    return run_bytes(["git", "show", f"{commit}:{path}"])


def committed_json(commit: str, path: str) -> object:
    return json.loads(committed_bytes(commit, path).decode("utf-8"))


def load_notices(commit: str) -> tuple[dict[str, dict[str, str]], bytes]:
    validate_revision(commit)
    document = committed_json(commit, "scripts/release/third_party_notices.json")
    expected_pins = set()
    for pin in committed_json(commit, "Package.resolved")["pins"]:
        identity = pin["identity"]
        expected_pins.add(identity)
        notice = document.get(identity)
        if not notice or pin["state"]["revision"] != notice["revision"]:
            raise ValueError(f"missing or stale third-party notice for {identity}")
        actual = hashlib.sha256(committed_bytes(commit, notice["licenseFile"])).hexdigest()
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
        license_bytes = committed_bytes(commit, notice["licenseFile"])
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
            "buildOptions": swift_build_flags(host_target()[0])[1:],
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


def run_bytes(command: list[str], cwd: Path | None = None) -> bytes:
    result = subprocess.run(command, cwd=ROOT if cwd is None else cwd, capture_output=True, check=False)
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


def build(source: Path, scratch: Path, os_name: str) -> Path:
    flags = swift_build_flags(os_name)
    run(["swift", "build", "--package-path", str(source), "--scratch-path", str(scratch), *flags], stdout=sys.stderr)
    binary = run(["swift", "build", "--package-path", str(source), "--scratch-path", str(scratch), *flags, "--show-bin-path"])
    products = Path(binary)
    executable = products / "refract"
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError("SwiftPM did not produce an executable refract product")
    strip_executable(executable, os_name)
    resource_bundle(products)
    return products


def binary_entries(products: Path, commit: str, metadata: dict[str, object], notices: bytes) -> list[tuple[str, int, bytes]]:
    resource = resource_bundle(products).read_bytes()
    expected = committed_bytes(commit, "Sources/RefractMapping/Resources/refract.schema.json")
    if resource != expected:
        raise ValueError("packaged mapping schema differs from the source revision")
    entries = [
        ("bin/refract", 0o755, (products / "refract").read_bytes()),
        ("LICENSE", 0o644, committed_bytes(commit, "LICENSE")),
        ("THIRD-PARTY-NOTICES.txt", 0o644, notices),
        ("BUILD-INFO.json", 0o644, json.dumps({
            "formatVersion": 1,
            "packageVersion": VERSION,
            "sourceRevision": commit,
            **metadata,
            "runtimeDependencyPolicy": "Linux statically links the Swift runtime; macOS uses the OS-provided Swift runtime. Generated apps have no Refract runtime dependency. System library requirements still apply.",
            "portability": "Native host binary only; OS, CPU, toolchain and runtime requirements apply. No cross-platform equivalence is claimed.",
        }, indent=2, sort_keys=True).encode("utf-8") + b"\n"),
    ]
    for name in ("Package.swift", "Package.resolved"):
        entries.append((f"source/{name}", 0o644, committed_bytes(commit, name)))
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
        resource = resource_bundle(extracted / "lib")
        if resource.read_bytes() != committed_bytes(commit, "Sources/RefractMapping/Resources/refract.schema.json"):
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
    products = build(source_root, scratch / "swift-build", os_name)
    archive = destination / f"refract-{VERSION}-{os_name}-{architecture}.tar.gz"
    entries = binary_entries(products, commit, metadata, notices)
    archive.write_bytes(gzip.compress(deterministic_tar(f"refract-{VERSION}-{os_name}-{architecture}", entries),
                                       compresslevel=9, mtime=ARCHIVE_EPOCH))
    installed = scratch / "installed"
    installed.mkdir()
    validate_package(archive, installed, commit)
    return archive


def verify_checksums(output: Path, archives: list[Path], os_name: str) -> None:
    """Verify checksum files without relying on the caller's working directory."""
    for archive in archives:
        checksum_path = archive.with_suffix(archive.suffix + ".sha256")
        digest, separator, name = checksum_path.read_text(encoding="ascii").strip().partition("  ")
        if not separator or name != archive.name or digest != hashlib.sha256(archive.read_bytes()).hexdigest():
            raise ValueError(f"checksum manifest mismatch for {archive.name}")
        if os_name == "macos":
            checker = ["shasum", "-a", "256", "--check", checksum_path.name]
        else:
            checker = ["sha256sum", "--check", "--strict", checksum_path.name]
        if not shutil.which(checker[0]):
            raise ValueError(f"{checker[0]} is required to verify the local archive checksum")
        print(run(checker, cwd=output))


def create_package(commit: str, output: Path, reproducible: bool) -> Path:
    os_name, architecture, triple = host_target()
    # Validate every legal/build input before host-tool checks, extraction or compilation.
    _, notices = load_notices(commit)
    for path in ("LICENSE", "Package.swift", "Sources/RefractMapping/Resources/refract.schema.json"):
        committed_bytes(commit, path)
    metadata = check_tools(triple)
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
        verify_checksums(output, [first, source], os_name)
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
