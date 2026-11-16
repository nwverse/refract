#!/usr/bin/env python3
"""Regenerate and validate the example sources without hiding platform verification gaps.

Run from the repository root after `swift build`:
    python3 scripts/check_examples.py

This is a generation and resource consistency check, not an Android, ArkTS or
SwiftUI compiler. Each example README gives its real toolchain build command.
"""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent


def fail(message: str) -> None:
    raise ValueError(message)


def regenerate_hello() -> None:
    outputs = {
        "kotlin": ROOT / "examples/android/app/src/main/java/refract/generated",
        "arkts": ROOT / "examples/harmony/entry/src/main/ets/generated",
    }
    sources = ("Hello.swift", "NativeComponentScreen.swift")
    with tempfile.TemporaryDirectory(prefix="refract-example-check.") as temporary:
        output = Path(temporary)
        for source in sources:
            command = [
                str(ROOT / ".build/debug/refract"),
                "generate",
                "--input", str(ROOT / "examples/shared" / source),
            ]
            if source != "Hello.swift":
                command += ["--mapping", str(ROOT / "examples/refract.json")]
            command += [
                "--android-out", str(output / "android"),
                "--harmony-out", str(output / "harmony"),
            ]
            subprocess.run(command, cwd=ROOT, check=True)
            for platform, directory in outputs.items():
                extension = "kt" if platform == "kotlin" else "ets"
                actual = output / ("android" if platform == "kotlin" else "harmony") / f"{Path(source).stem}.{extension}"
                expected = directory / f"{Path(source).stem}.{extension}"
                if actual.read_bytes() != expected.read_bytes():
                    fail(f"regenerated {platform} differs from {expected.relative_to(ROOT)}; regenerate and review it")
    print("Hello and native-component Kotlin/ArkTS are identical to actual regenerated output")


def check_resources() -> None:
    mapping = json.loads((ROOT / "examples/refract.json").read_text(encoding="utf-8"))
    if mapping.get("schemaVersion") != 1:
        fail("example mapping must use the current schemaVersion 1 registry")
    android = mapping["android"]["resources"]["strings"]
    harmony = mapping["harmonyOS"]["resources"]["strings"]
    if android != harmony:
        fail("Android and HarmonyOS string registries differ")
    if set(android) != {
        "settings.profile", "settings.display.name", "settings.preferences",
        "settings.notifications", "settings.save", "settings.native.component",
    }:
        fail("settings resource registry does not match the shared source keys")

    android_path = ROOT / "examples/android/app/src/main/res/values/strings.xml"
    android_root = ET.parse(android_path).getroot()
    android_names = {child.attrib["name"] for child in android_root.findall("string")}
    harmony_path = ROOT / "examples/harmony/entry/src/main/resources/base/element/string.json"
    harmony_names = {entry["name"] for entry in json.loads(harmony_path.read_text())["string"]}
    for key, native_name in android.items():
        if native_name != key.replace(".", "_"):
            fail(f"resource name for {key} is not its normalized form")
        if native_name not in android_names:
            fail(f"Android base string catalog is missing {native_name}")
        if native_name not in harmony_names:
            fail(f"HarmonyOS base string catalog is missing {native_name}")
    if mapping["android"]["resources"]["className"] != "com.example.refract.R":
        fail("generated Compose must use the application R class, not a generated-package R class")
    ios_keys = set()
    ios_path = ROOT / "examples/ios/RefractExample/en.lproj/Localizable.strings"
    for line in ios_path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("//"):
            continue
        key, separator, _ = line.partition("=")
        if not separator:
            fail(f"invalid iOS localized string declaration: {line}")
        ios_keys.add(key.strip().strip('"'))
    if ios_keys != set(android):
        fail("iOS and generated-platform localized key sets differ")
    print("Android, HarmonyOS and iOS base catalogs contain every mapped settings key")


def check_harmony_resources() -> None:
    root = ROOT / "examples/harmony"
    for relative in (
        "AppScope/resources/base/media/app_icon.svg",
        "entry/src/main/resources/base/media/app_icon.svg",
    ):
        path = root / relative
        if not path.is_file():
            fail(f"missing HarmonyOS media resource: {relative}")
        icon = ET.parse(path).getroot()
        if not icon.tag.endswith("svg"):
            fail(f"invalid HarmonyOS SVG resource: {relative}")
    for relative in ("AppScope/app.json5", "entry/src/main/module.json5"):
        if '"$media:app_icon"' not in (root / relative).read_text(encoding="utf-8"):
            fail(f"expected app_icon reference is missing from {relative}")
    print("HarmonyOS application and ability icon resources exist")


def check_ios_references() -> None:
    project = (ROOT / "examples/ios/RefractExample.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    for name in ("Hello", "SettingsScreen", "NativeComponentScreen"):
        path = f"../shared/{name}.swift"
        if project.count(path) < 1:
            fail(f"iOS target does not reference {path}")
        if project.count(f"{name}.swift in Sources") < 2:
            fail(f"iOS target does not compile {path}")
    print("iOS project references every shared Swift source in its Sources phase")


def main() -> int:
    try:
        regenerate_hello()
        check_resources()
        check_harmony_resources()
        check_ios_references()
    except (KeyError, ValueError, OSError, subprocess.CalledProcessError, ET.ParseError) as error:
        print(f"check_examples: {error}", file=sys.stderr)
        return 1
    print("Example consistency checks passed; native compilation remains a separate toolchain check")
    return 0


if __name__ == "__main__":
    sys.exit(main())
