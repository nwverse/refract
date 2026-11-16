#!/usr/bin/env python3
"""Regenerate the canonical fixture corpus through the refract CLI, diff the
output against Expected.kt, and stage the Kotlin plus the fixture's Android
resources under examples/android/fixtures/src/main/ so the standard Gradle
toolchain can compile them.

Run from the repository root after `swift build`:

    python3 scripts/check_fixture_compilation.py

After the script succeeds, run `./gradlew :fixtures:compileDebugKotlin` from
`examples/android/` to compile the staged sources. The staged files are
.gitignored: they are produced on every CI run and never committed.

The set of fixtures compiled is driven by examples/android/fixture-compile-manifest.txt
(one directory name per line under Fixtures/, # starts a comment). Adding a
fixture is a manifest-only change. There is no skip list: any compile failure
must be fixed in the same PR that introduces it, and removing a manifest entry
without a tracked reason is forbidden because it silently reduces the corpus
the compiler sees.

This is a compile-only gate. It produces no APK, no emulator run, no device
measurement and no performance claim (goal 2 of docs/GOALS.md).
"""
from __future__ import annotations

from pathlib import Path
import json
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "examples/android/fixture-compile-manifest.txt"
FIXTURES_ROOT = ROOT / "Fixtures"
STAGING_JAVA = ROOT / "examples/android/fixtures/src/main/java"
STAGING_RES = ROOT / "examples/android/fixtures/src/main/res/values"


def fail(message: str) -> None:
    raise ValueError(message)


def read_manifest() -> list[str]:
    if not MANIFEST.is_file():
        fail(f"manifest not found: {MANIFEST.relative_to(ROOT)}")
    names: list[str] = []
    for raw in MANIFEST.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            names.append(line)
    if not names:
        fail(f"manifest lists no fixtures: {MANIFEST.relative_to(ROOT)}")
    return names


def regenerate_and_stage(fixture: str) -> None:
    fixture_dir = FIXTURES_ROOT / fixture
    if not fixture_dir.is_dir():
        fail(f"manifest entry is not a fixture directory: {fixture}")
    input_swift = fixture_dir / "Input.swift"
    expected_kt = fixture_dir / "Expected.kt"
    mapping_json = fixture_dir / "refract.json"
    strings_xml = fixture_dir / "values/strings.xml"
    for path in (input_swift, expected_kt, mapping_json, strings_xml):
        if not path.is_file():
            fail(f"{fixture}: missing required file {path.relative_to(ROOT)}")

    with tempfile.TemporaryDirectory(prefix=f"refract-fixture-{fixture}-") as tmp:
        out = Path(tmp)
        subprocess.run(
            [
                str(ROOT / ".build/debug/refract"),
                "generate",
                "--input", str(input_swift),
                "--mapping", str(mapping_json),
                "--android-out", str(out / "android"),
                "--harmony-out", str(out / "harmony"),
            ],
            cwd=ROOT,
            check=True,
        )
        regenerated = out / "android/Input.kt"
        if not regenerated.is_file():
            fail(f"{fixture}: CLI did not produce android/Input.kt")
        if regenerated.read_bytes() != expected_kt.read_bytes():
            fail(
                f"{fixture}: regenerated Kotlin differs from {expected_kt.relative_to(ROOT)}; "
                "regenerate and review it"
            )

    # Preserve each fixture's declared package while sharing the fixture module's R class.
    # Android library R classes are generated in the Gradle namespace, not each Kotlin subpackage.
    package = json.loads(mapping_json.read_text(encoding="utf-8"))["android"]["output"]["packageName"]
    namespace = "refract.generated"
    package_directory = STAGING_JAVA.joinpath(*package.split("."))
    package_directory.mkdir(parents=True, exist_ok=True)
    generated = expected_kt.read_text(encoding="utf-8").replace(
        f"{package}.R.", f"{namespace}.R."
    ).replace(f"import {package}.R\n", f"import {namespace}.R\n")
    if package != namespace and f"import {namespace}.R\n" not in generated and f"stringResource(R.string." in generated:
        generated = generated.replace(
            f"package {package}\n", f"package {package}\n\nimport {namespace}.R\n", 1
        )
    target = package_directory / f"{fixture}.kt"
    target.write_text(generated, encoding="utf-8")
    STAGING_RES.mkdir(parents=True, exist_ok=True)
    # Each fixture brings its own values/strings.xml. Concatenate the entries
    # into a single staged strings.xml so that resources with the same name do
    # not silently override each other.
    merge_strings(strings_xml, STAGING_RES / "strings.xml", fixture)


def merge_strings(source: Path, target: Path, fixture: str) -> None:
    """Append <string> entries from `source` into `target`.

    Each fixture has its own strings.xml with a single `<resources>` root. The
    staged file accumulates every fixture's entries. Duplicate string names with
    different values are rejected: they would otherwise let one fixture shadow
    another's resource. Identical duplicates are deduplicated silently because
    they describe the same shared resource.
    """
    source_root = ET.parse(source).getroot()
    source_entries = [(child.attrib["name"], (child.text or "").strip())
                      for child in source_root.findall("string")]
    # Model-only fixtures may legitimately have no localized resources. Keep an
    # empty root so a later fixture can merge its entries into the same catalog.
    if target.exists():
        target_root = ET.parse(target).getroot()
    else:
        target_root = ET.Element("resources")
        target_root.text = "\n"
    existing: dict[str, str] = {child.attrib["name"]: (child.text or "").strip()
                                for child in target_root.findall("string")}
    for name, value in source_entries:
        if name in existing:
            if existing[name] != value:
                fail(
                    f"{fixture}: string name '{name}' already staged with a different value; "
                    "rename one of the keys or align the values"
                )
            # Identical value: the fixture just confirms the same resource.
            continue
        child = ET.SubElement(target_root, "string", name=name)
        child.text = value
        existing[name] = value
    ET.indent(target_root, space="  ")
    ET.ElementTree(target_root).write(target, encoding="utf-8", xml_declaration=True)


def main() -> int:
    try:
        fixtures = read_manifest()
        # Start with a clean staging area so a fixture removed from the manifest
        # cannot leave stale Kotlin behind for Gradle to compile.
        for path in (STAGING_JAVA, STAGING_RES):
            if path.exists():
                shutil.rmtree(path)
        for fixture in fixtures:
            regenerate_and_stage(fixture)
        print(f"Staged {len(fixtures)} fixture(s) under examples/android/fixtures/src/main/")
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"check_fixture_compilation: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
