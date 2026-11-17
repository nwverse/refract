#!/usr/bin/env python3
"""Exercise the actual SwiftPM consumer integration in an isolated temporary workspace.

The Linux-only syntax module is test scaffolding, not a SwiftUI implementation or
an app runtime. The committed consumer source remains ordinary SwiftUI; macOS
runs the same host build against Apple's real SwiftUI module.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def run(arguments: list[str], cwd: Path, env: dict[str, str], *, expected: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(arguments, cwd=cwd, env=env, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=300, check=False)
    if result.returncode != expected:
        print(result.stdout, file=sys.stderr)
        raise AssertionError(f"exit {result.returncode}, expected {expected}: {' '.join(arguments)}")
    return result


def write_manifest(path: Path, linux: bool) -> None:
    if sys.platform != "darwin":
        dependency = '\n            dependencies: ["SwiftUI"],'
        support = '\n        .target(name: "SwiftUI"),'
    else:
        dependency = ""
        support = ""
    path.write_text(f'''// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RefractConsumer",
    platforms: [.macOS(.v13)],
    products: [.library(name: "RefractConsumer", targets: ["RefractConsumer"])],
    dependencies: [.package(path: "../refract")],
    targets: [
        .target(
            name: "RefractConsumer",{dependency}
            exclude: ["refract.json", "strings.xml", "string.json"],
            plugins: [.plugin(name: "RefractSwiftPMPlugin", package: "refract")]
        ),{support}
    ]
)
''', encoding="utf-8")


def prepare(root: Path, linux: bool) -> tuple[Path, dict[str, str]]:
    consumer = root / "consumer"
    shutil.copytree(ROOT / "examples/swiftpm-consumer", consumer,
                    ignore=shutil.ignore_patterns(".build", ".swiftpm"))
    # A relative symlink preserves relocatability while exposing the exact source
    # package to the consumer. Tests never publish this temporary link.
    (root / "refract").symlink_to(ROOT, target_is_directory=True)
    write_manifest(consumer / "Package.swift", linux)
    if linux:
        support = consumer / "Sources/SwiftUI"
        support.mkdir()
        (support / "SwiftUI.swift").write_text('''public protocol View {}
public struct VStack: View { public init(@ViewBuilder content: () -> [any View]) {} }
public struct Text: View { public init(_ key: String) {} }
public struct Button: View { public init(_ key: String, action: () -> Void) {} }
@resultBuilder public enum ViewBuilder {
    public static func buildBlock(_ content: any View...) -> [any View] { content }
}
public extension View { var body: some View { self } }
''', encoding="utf-8")
    env = dict(os.environ)
    env["REFRACT_EXECUTABLE"] = str(ROOT / ".build/debug/refract")
    return consumer, env


def swift(arguments: list[str], consumer: Path, env: dict[str, str], *, expected: int = 0,
          verbose: bool = False) -> subprocess.CompletedProcess[str]:
    command = ["swift"] + (["package"] if arguments != ["build"] else []) + arguments
    if arguments == ["build"]:
        command += ["-j", "4"]
    if verbose:
        command.append("-v")
    return run(command, consumer, env, expected=expected)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep", type=Path, help="Keep the temporary test directory for inspection")
    args = parser.parse_args()
    if not (ROOT / ".build/debug/refract").is_file():
        raise AssertionError("Run swift build before the consumer integration test")
    temporary = tempfile.TemporaryDirectory(prefix="refract-swiftpm-consumer.")
    workspace = Path(args.keep) if args.keep else Path(temporary.name)
    if args.keep:
        workspace.mkdir(parents=True, exist_ok=False)
    consumer, env = prepare(workspace, sys.platform != "darwin")
    source = consumer / "Sources/RefractConsumer/Hello.swift"
    committed = consumer / "Generated/Android/Hello.kt"
    original_committed = committed.read_bytes()
    outputs = consumer / ".build/plugins/outputs/consumer/RefractConsumer/destination/RefractBuildTool"

    # Explicit publication is the only write path. Ordinary builds regenerate into
    # their plugin work directory and compare committed outputs without modifying them.
    swift(["build"], consumer, env)
    manifest = run(["swift", "package", "--package-path", str(consumer), "describe", "--type", "json"],
                   consumer, env)
    host = next(item for item in json.loads(manifest.stdout)["targets"]
                if item["name"] == "RefractConsumer")
    assert host["product_dependencies"] == ["RefractSwiftPMPlugin"]
    assert all("refract" not in dependency.lower()
               for dependency in host.get("target_dependencies", []))
    staged_kotlin = (outputs / "Android/Hello.kt").read_bytes()
    staged_arkts = (outputs / "HarmonyOS/Hello.ets").read_bytes()
    assert staged_kotlin == original_committed
    assert staged_arkts == (consumer / "Generated/HarmonyOS/Hello.ets").read_bytes()
    assert (outputs / "RefractBuildAnchor.swift").read_text() == "// Generated build-order anchor; no Refract runtime.\n"
    first_stamp = (outputs / "Android/Hello.kt").stat().st_mtime_ns

    # The host target depends only on the Linux probe syntax module, if needed;
    # it never links a Refract product or a generated native runtime.
    target_manifest = (ROOT / "examples/swiftpm-consumer/Package.swift").read_text()
    assert '.plugin(name: "RefractSwiftPMPlugin", package: "refract")' in target_manifest
    assert "platforms: [.macOS(.v13)]" in target_manifest
    assert 'dependencies: [.package(path: "../refract")]' in target_manifest
    assert 'dependencies: ["Refract' not in target_manifest
    assert not (consumer / "Sources/RefractConsumer/Generated").exists()

    second = swift(["build"], consumer, env, verbose=True)
    assert "--target RefractConsumer --plugin-work" not in second.stdout, second.stdout
    assert (outputs / "Android/Hello.kt").stat().st_mtime_ns == first_stamp
    assert committed.read_bytes() == original_committed

    committed.write_bytes(original_committed + b"// deliberately stale\n")
    stale = swift(["build"], consumer, env, expected=1)
    assert "stale committed output" in stale.stdout.lower() and "Hello.kt" in stale.stdout, stale.stdout
    assert committed.read_bytes().endswith(b"// deliberately stale\n")
    committed.write_bytes(original_committed)

    # Every declared input class is passed to SwiftPM's buildCommand. Use mtime-only
    # changes so regeneration itself remains byte deterministic.
    dependencies = [consumer / "refract-swiftpm.json", source, consumer / "Sources/RefractConsumer/refract.json",
                    consumer / "Sources/RefractConsumer/strings.xml",
                    consumer / "Sources/RefractConsumer/string.json", committed]
    for dependency in dependencies:
        previous = dependency.stat().st_mtime_ns
        os.utime(dependency, ns=(previous + 2_000_000_000, previous + 2_000_000_000))
        rebuilt = swift(["build"], consumer, env, verbose=True)
        assert "--target RefractConsumer --plugin-work" in rebuilt.stdout, rebuilt.stdout
        assert "Generate and verify native sources with Refract" in rebuilt.stdout
        assert (outputs / "Android/Hello.kt").read_bytes() == original_committed
        noop = swift(["build"], consumer, env, verbose=True)
        assert "--target RefractConsumer --plugin-work" not in noop.stdout, dependency

    committed.unlink()
    missing = swift(["build"], consumer, env, expected=1)
    assert "missing committed output" in missing.stdout.lower() or "Build input files cannot be found" in missing.stdout, missing.stdout
    swift(["refract-generate", "--target", "RefractConsumer", "--allow-writing-to-package-directory"],
          consumer, env)
    assert committed.read_bytes() == original_committed

    # A newly added direct native file changes the declared output-directory manifest.
    # The CLI rejects it; a later clean check must not report it again after removal.
    obsolete = committed.with_name("Obsolete.kt")
    obsolete.write_text("// unexpected native output\n")
    unexpected = swift(["build"], consumer, env, expected=1)
    assert "unexpected generated output" in unexpected.stdout and "Obsolete.kt" in unexpected.stdout, unexpected.stdout
    assert obsolete.exists()
    obsolete.unlink()
    swift(["build"], consumer, env)

    # An invalid explicit override is diagnosed by the build-tool plugin rather than
    # being silently replaced with a downloaded or unrelated CLI.
    broken = dict(env)
    broken["REFRACT_EXECUTABLE"] = str(consumer / "not-an-executable")
    missing_tool = swift(["build"], consumer, broken, expected=1)
    assert "REFRACT_EXECUTABLE is not an executable file" in missing_tool.stdout
    broken["REFRACT_EXECUTABLE"] = str(consumer)
    directory_tool = swift(["build"], consumer, broken, expected=1)
    assert "REFRACT_EXECUTABLE is not an executable file" in directory_tool.stdout
    assert "NSCocoaErrorDomain" not in directory_tool.stdout

    # Read-only checking is a separate command plugin with no package-write
    # permission. It must preserve stale output and fail with the CLI diagnostic.
    committed.write_bytes(original_committed + b"// read-only check must fail\n")
    checked = swift(["refract-check", "--target", "RefractConsumer"], consumer, env, expected=1)
    assert "stale committed output" in checked.stdout.lower() and "Hello.kt" in checked.stdout, checked.stdout
    assert committed.read_bytes().endswith(b"// read-only check must fail\n")
    committed.write_bytes(original_committed)

    # Reject a configured output directory that is a symlink to a package-external
    # directory before the tool attempts to write through command-plugin permission.
    generated = consumer / "Generated/Android"
    shutil.rmtree(generated)
    (workspace / "outside").mkdir()
    generated.symlink_to(workspace / "outside", target_is_directory=True)
    symlink = swift(["build"], consumer, env, expected=1)
    assert "outside the consuming package" in symlink.stdout or "must not traverse a symbolic link" in symlink.stdout

    print("PASS: real SwiftPM generation, explicit staging, input invalidation, no-op scheduling, fail-closed checks and sandbox boundaries")
    if sys.platform != "darwin":
        print("LIMIT: Linux used an isolated syntax-only SwiftUI module; this is not SwiftUI/iOS compilation or device evidence")
    if not args.keep:
        temporary.cleanup()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
