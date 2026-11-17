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
        "kotlin": ROOT / "examples/android/app/refract/generated/screens",
        "arkts": ROOT / "examples/harmony/entry/src/main/ets/generated",
    }
    sources = ("Hello.swift", "NativeComponentScreen.swift", "SettingsScreen.swift")
    with tempfile.TemporaryDirectory(prefix="refract-example-check.") as temporary:
        output = Path(temporary)
        for source in sources:
            command = [
                str(ROOT / ".build/debug/refract"),
                "generate",
                "--input", str(ROOT / "examples/shared" / source),
            ]
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
    print("Hello, native-component and full-settings Kotlin/ArkTS are identical to actual regenerated output")


def regenerate_identified_list() -> None:
    outputs = {
        "android": ROOT / "examples/android/app/refract/generated/screens/IdentifiedList.kt",
        "harmony": ROOT / "examples/harmony/entry/src/main/ets/generated/IdentifiedList.ets",
    }
    source = ROOT / "examples/shared/IdentifiedList.swift"
    canonical = ROOT / "Fixtures/v0-identified-list/Input.swift"
    if source.read_bytes() != canonical.read_bytes():
        fail("the identified-list example must retain the canonical Swift input")
    with tempfile.TemporaryDirectory(prefix="refract-list-example-check.") as temporary:
        output = Path(temporary)
        subprocess.run([
            str(ROOT / ".build/debug/refract"), "generate", "--input", str(source),
            "--mapping", str(ROOT / "examples/refract.json"),
            "--android-out", str(output / "android"), "--harmony-out", str(output / "harmony"),
        ], cwd=ROOT, check=True)
        for platform, expected in outputs.items():
            actual = output / platform / expected.name
            if actual.read_bytes() != expected.read_bytes():
                fail(
                    f"regenerated identified-list {platform} differs from "
                    f"{expected.relative_to(ROOT)}; regenerate and review it"
                )
    print("Identified-list Kotlin/ArkTS are identical to actual regenerated project-mapped output")


    source = ROOT / "examples/shared/SettingsScreen.swift"
    canonical = ROOT / "Fixtures/v0-settings-screen/Input.swift"
    if source.read_bytes() != canonical.read_bytes():
        fail("the settings example must retain the canonical model/state/binding source")
def check_resources() -> None:
    source = ROOT / "examples/shared/SettingsScreen.swift"
    canonical = ROOT / "Fixtures/v0-settings-screen/Input.swift"
    if source.read_bytes() != canonical.read_bytes():
        fail("the settings example must retain the canonical model/state/binding source")
    print("Settings example retains the canonical model/state/binding source")

    mapping = json.loads((ROOT / "examples/refract.json").read_text(encoding="utf-8"))
    if mapping.get("schemaVersion") != 1:
        fail("example mapping must use the current schemaVersion 1 registry")
    android = mapping["android"]["resources"]["strings"]
    harmony = mapping["harmonyOS"]["resources"]["strings"]
    if android != harmony:
        fail("Android and HarmonyOS string registries differ")
    if set(android) != {
        "example.hello", "example.go",
        "conversation.answer", "conversation.important", "conversation.note", "conversation.docs", "conversation.code.label",
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
    # Unique on-disk basenames avoid Xcode's shared Input.stringsdata output.
    # These are source-only compiler inputs, never independently generated screens.
    compiler_inputs = {
        "InteropNativeMeasurement": "interop-native-measurement",
        "InteropPlatformValue": "interop-platform-value",
        "InteropPlatformView": "interop-platform-view",
        "StateCounter": "state-counter",
        "ParentBinding": "parent-binding",
        "ModelInterface": "model-interface",
        "AccessibilityDynamicType": "accessibility-dynamic-type",
        "StackLayout": "v0-stack-layout",
        "MarkdownConversation": "markdown-conversation",
    }
    for name, case in compiler_inputs.items():
        path = f"../shared/{name}.swift"
        if project.count(path) != 1 or project.count(f"{name}.swift in Sources") != 2:
            fail(f"iOS target must compile the uniquely named {name} source exactly once")
        shared = ROOT / "examples/shared" / f"{name}.swift"
        canonical = ROOT / "Fixtures" / case / "Input.swift"
        if shared.read_bytes() != canonical.read_bytes():
            fail(f"{path} must remain byte-identical to the canonical {case} fixture")
    if project.count("Input.swift") or "Fixtures/" in project:
        fail("iOS target must not compile multiple canonical files named Input.swift")
    if not (ROOT / "examples/ios/RefractExample/MeasurementDesignTokens.swift").is_file():
        fail("iOS target is missing the measurement fixture's application-owned typography token")
    if not (ROOT / "examples/ios/RefractExample/RefractMarkdownSource.swift").is_file():
        fail("iOS target is missing the typed Markdown source declarations")
    print("iOS project compiles every shared source and nine unique, byte-identical compiler inputs")


def main() -> int:
    try:
        regenerate_hello()
        regenerate_identified_list()
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
