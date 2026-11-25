#!/usr/bin/env python3
"""Portable source-contract checks; these are not native compilation or timing."""

import json
import re
import shutil
import tempfile
import unittest
from pathlib import Path


HARMONY_SOURCES = {
    "generated": "entry/src/main/ets/generated/SettingsScreen.ets",
    "reference": "entry/src/main/ets/native/ReferenceSettingsScreen.ets",
    "model": "entry/src/main/ets/native/SettingsModel.ets",
    "typography": "entry/src/main/ets/native/AppTypography.ets",
    "page": "entry/src/main/ets/pages/BenchmarkPage.ets",
    "mapping": "refract.json",
    "resources": "entry/src/main/resources/base/element/string.json",
    "application": "build-profile.json5",
    "entry": "entry/build-profile.json5",
    "module": "entry/src/main/module.json5",
}


HARMONY_ROW_CONTRACTS = {
    "generated": """
        Row() {
          Column() {
            Text(this.row.title).font(AppTypography.rowTitle)
            Text(this.row.subtitle).font(AppTypography.rowSubtitle)
          }.layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.row.enabled })
            .onChange((enabled: boolean) => {
              this.model.setEnabled(this.row.id, enabled);
            })
            .id(`setting_toggle_${this.row.id}`).accessibilityText(this.row.title)
        }
        .alignItems(VerticalAlign.Center)
        .id(`setting_row_${this.row.id}`)
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    """,
    "reference": """
        Row() {
          Column() {
            Text(this.title)
              .font(AppTypography.rowTitle)
            Text(this.subtitle)
              .font(AppTypography.rowSubtitle)
          }
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.enabled })
            .onChange((value: boolean): void => this.onChange(value))
            .id(`setting_toggle_${this.id}`)
            .accessibilityText(this.title)
        }
        .alignItems(VerticalAlign.Center)
        .id(`setting_row_${this.id}`)
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    """,
}


def source_tokens(source: str) -> str:
    """Remove comments and layout whitespace outside literals; this is not an ArkTS parser."""
    tokens = []
    index = 0
    quote = None
    escaped = False
    line_comment = False
    block_comment = False
    while index < len(source):
        character = source[index]
        following = source[index + 1] if index + 1 < len(source) else ""
        if line_comment:
            if character == "\n":
                line_comment = False
        elif block_comment:
            if character == "*" and following == "/":
                block_comment = False
                index += 1
        elif quote is not None:
            tokens.append(character)
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = None
        elif character == "/" and following == "/":
            line_comment = True
            index += 1
        elif character == "/" and following == "*":
            block_comment = True
            index += 1
        elif character in ('"', "'", "`"):
            quote = character
            tokens.append(character)
        elif not character.isspace():
            tokens.append(character)
        index += 1
    return "".join(tokens)


def declaration_body(tokens: str, declaration: str) -> str | None:
    """Return one declaration's balanced body, or None for an ambiguous/unbounded shape."""
    if tokens.count(declaration) != 1:
        return None
    opening = tokens.index(declaration) + len(declaration)
    if opening >= len(tokens) or tokens[opening] != "{":
        return None
    depth = 0
    for index in range(opening, len(tokens)):
        if tokens[index] == "{":
            depth += 1
        elif tokens[index] == "}":
            depth -= 1
            if depth == 0:
                return tokens[opening:index + 1]
            if depth < 0:
                return None
    return None


def unique_json_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate object key: {key}")
        result[key] = value
    return result


def reject_nonfinite_json_constant(constant: str) -> None:
    """Keep Python's non-standard JSON5 constants outside the strict JSON subset."""
    raise ValueError(f"non-finite JSON number is unsupported: {constant}")


def harmony_source_contract_errors(harmony: Path) -> list[str]:
    """Check bounded source identities, not ArkTS grammar or compiler acceptance."""
    sources = {}
    errors = []
    for name, relative in HARMONY_SOURCES.items():
        path = harmony / relative
        if not path.is_file():
            errors.append(f"missing source: {relative}")
            continue
        sources[name] = path.read_text(encoding="utf-8")

    def require(owner: str, fragment: str) -> None:
        if owner in sources and sources[owner].count(fragment) != 1:
            errors.append(f"{HARMONY_SOURCES[owner]} must contain exactly once: {fragment}")

    require("generated", "// Generated by Refract; DO NOT EDIT.")
    require("generated", "@ObservedV2\nexport class SettingRow")
    for name, type_name in (("id", "number"), ("title", "string"),
                            ("subtitle", "string"), ("enabled", "boolean")):
        require("generated", f"@Trace {name}: {type_name};")
    require("model", "import { SettingRow, SettingsModel } from '../generated/SettingsScreen';")
    require("model", "export class BenchmarkRows extends BasicDataSource<SettingRow>")
    require("model", "@ObservedV2\nexport class BenchmarkSettingsModel implements SettingsModel")
    require("model", "for (let id = 0; id < 200; id++)")
    require("model", "const previous = this.rows[index];")
    require("model", "this.rows[index] = new SettingRow(id, previous.title, previous.subtitle, enabled);")
    require("model", "this.notifyDataChange(index);")
    if "model" in sources:
        model_tokens = source_tokens(sources["model"])
        model_body = declaration_body(
            model_tokens, "exportclassBenchmarkSettingsModelimplementsSettingsModel")
        if model_body is None:
            errors.append("the shared model must have one unambiguous BenchmarkSettingsModel declaration")
        else:
            set_enabled = declaration_body(model_body, "setEnabled(id:number,value:boolean):void")
            if set_enabled is None or set_enabled != "{this.rows.replaceRow(id,value);}":
                errors.append("BenchmarkSettingsModel.setEnabled must only delegate to this.rows.replaceRow(id, value)")
    if "reference" in sources:
        reference_tokens = source_tokens(sources["reference"])
        reference_body = declaration_body(reference_tokens, "exportstructReferenceSettingsScreen")
        reference_callback = source_tokens(
            "onChange: (value: boolean): void => this.model.setEnabled(row.id, value),")
        if reference_body is None or reference_body.count(reference_callback) != 1:
            errors.append("the reference row must delegate its callback to this.model.setEnabled(row.id, value)")
    for owner, contract in HARMONY_ROW_CONTRACTS.items():
        if owner in sources:
            tokens = source_tokens(sources[owner])
            if tokens.count(source_tokens(contract)) != 1:
                errors.append(f"{HARMONY_SOURCES[owner]} must retain the paired row typography, "
                              "switch/accessibility wiring and stable layout exactly once")
    if "model" in sources and re.search(r"\.enabled\s*=(?!=)", sources["model"]):
        errors.append("the shared model must replace rows rather than mutate enabled in place")
    require("reference", "import { BenchmarkSettingsModel } from './SettingsModel';")
    require("reference", "@Require @Param model: BenchmarkSettingsModel;")
    require("reference", "import { SettingRow } from '../generated/SettingsScreen';")
    if "reference" in sources and "GeneratedSettingRow" in sources["reference"]:
        errors.append("the native reference must not call the generated row")
    for owner in ("generated", "reference"):
        if owner in sources:
            executable = source_tokens(sources[owner])
            if executable.count(source_tokens(f"LazyForEach(this.model.rows, (row: SettingRow)")) != 1:
                errors.append(f"{HARMONY_SOURCES[owner]} must use the shared lazy model data source")
            if executable.count(source_tokens("(row: SettingRow): string => String(row.id)")) != 1:
                errors.append(f"{HARMONY_SOURCES[owner]} must key rows by String(row.id)")
            if executable.count(source_tokens(".reuse({ reuseId: () => 'setting' })")) != 1:
                errors.append(f"{HARMONY_SOURCES[owner]} must retain the setting reuse identity")
    require("reference", ".accessibilityText(this.title)")
    require("page", "import { BenchmarkSettingsModel } from '../native/SettingsModel';")
    if "page" in sources:
        if re.search(r"(?m)^\s*SettingsScreen\(\{ model: this\.model \}\)$", sources["page"]) is None:
            errors.append(f"{HARMONY_SOURCES['page']} must invoke the generated screen with the shared model")
        if re.search(r"(?m)^\s*ReferenceSettingsScreen\(\{ model: this\.model \}\)$", sources["page"]) is None:
            errors.append(f"{HARMONY_SOURCES['page']} must invoke the reference with the shared model")

    if "mapping" in sources:
        try:
            mapping = json.loads(sources["mapping"])
            if mapping["harmonyOS"]["imports"] != [{
                "module": "../native/AppTypography",
                "symbols": ["AppTypography"],
            }]:
                errors.append("the typography import must name the app-owned native module")
            expected_resources = {
                "namespace": "app",
                "stringTable": "string",
                "catalog": "../android/resources/base/element/string.json",
                "strings": {"settings.item": "settings_item"},
            }
            if mapping["harmonyOS"]["resources"] != expected_resources:
                errors.append("the shared resource catalog mapping has changed")
        except (KeyError, TypeError, ValueError) as error:
            errors.append(f"invalid mapping contract: {error}")
    require("generated", "import { AppTypography } from '../native/AppTypography';")
    require("reference", "import { AppTypography } from './AppTypography';")
    require("typography", "export class AppTypography")
    if "resources" in sources:
        try:
            resources = json.loads(sources["resources"])
            if {"name": "settings_item", "value": "Setting %d"} not in resources["string"]:
                errors.append("the native settings_item string resource is missing")
        except (KeyError, TypeError, ValueError) as error:
            errors.append(f"invalid native string resource catalog: {error}")
    configurations = {}
    for owner in ("application", "entry", "module"):
        if owner not in sources:
            continue
        try:
            configurations[owner] = json.loads(sources[owner], object_pairs_hook=unique_json_object,
                                               parse_constant=reject_nonfinite_json_constant)
        except (TypeError, ValueError) as error:
            # These checked-in files use JSON5's strict JSON subset. Reject other syntax rather than
            # accepting text outside the declared objects or adding a new parser dependency.
            errors.append(f"invalid {HARMONY_SOURCES[owner]} structural contract: {error}")
    application = configurations.get("application")
    if application is not None:
        try:
            app = application["app"]
            products = app["products"]
            defaults = [product for product in products
                        if isinstance(product, dict) and product.get("name") == "default"]
            if len(defaults) != 1:
                errors.append("the application must contain exactly one default product")
            elif (defaults[0].get("compatibleSdkVersion"), defaults[0].get("runtimeOS")) != ("26.0.0", "HarmonyOS"):
                errors.append("the default product must declare compatibleSdkVersion 26.0.0 and HarmonyOS")
            if [(mode.get("name") if isinstance(mode, dict) else None,
                 set(mode) if isinstance(mode, dict) else None)
                    for mode in app["buildModeSet"]] != [("debug", {"name"}), ("release", {"name"})]:
                errors.append("app.buildModeSet must contain only the debug and release name declarations")
        except (AttributeError, IndexError, KeyError, TypeError) as error:
            errors.append(f"invalid application product/build-mode structure: {error}")
    entry = configurations.get("entry")
    if entry is not None:
        try:
            options = entry["buildOptionSet"]
            if len(options) != 1 or not isinstance(options[0], dict) or options[0].get("name") != "release":
                errors.append("the entry buildOptionSet must contain exactly one Release option")
        except (AttributeError, IndexError, KeyError, TypeError) as error:
            errors.append(f"invalid entry build-option structure: {error}")
    module = configurations.get("module")
    if module is not None:
        try:
            if (module["module"].get("name"), module["module"].get("pages")) != ("entry", "$profile:main_pages"):
                errors.append("the entry module must declare its own name and main_pages profile")
        except (AttributeError, KeyError, TypeError) as error:
            errors.append(f"invalid module declaration structure: {error}")
    return errors


class BenchmarkSourceContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(__file__).resolve().parents[2]
        cls.ios = cls.root / "bench/ios"
        cls.harmony = cls.root / "bench/harmony"

    def test_ios_references_the_canonical_shared_source(self):
        project = (self.ios / "RefractBench.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        self.assertIn("../android/SettingsScreen.swift", project)
        self.assertIn("fileRef = AA1670000000000000000008", project)
        self.assertIn("AA167000000000000000000A);", project)
        self.assertFalse((self.ios / "RefractBench/SettingsScreen.swift").exists())
        self.assertIn("SettingsScreen(model: model)",
                      (self.ios / "RefractBench/GeneratedSettingsScreen.swift").read_text(encoding="utf-8"))

    def test_ios_ui_test_target_binds_the_application_under_test(self):
        project = (self.ios / "RefractBench.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        self.assertEqual(project.count("TEST_TARGET_NAME = RefractBench;"), 2)

    def test_native_reference_is_separate_and_preserves_row_behavior(self):
        reference = (self.ios / "RefractBench/ReferenceSettingsScreen.swift").read_text(encoding="utf-8")
        code = "\n".join(line for line in reference.splitlines() if not line.lstrip().startswith("//"))
        self.assertNotIn("GeneratedSettingRow", code)
        self.assertIn("ReferenceSettingRow", reference)
        self.assertIn(".accessibilityLabel(Text(title))", reference)
        self.assertIn(".layoutPriority(1)", reference)
        model = (self.ios / "RefractBench/SettingsModel.swift").read_text(encoding="utf-8")
        self.assertIn("static let rowCount = 200", model)
        self.assertIn("@Published private(set) var rows", model)

    def test_harmony_uses_actual_generated_screen_and_separate_reference(self):
        self.assertEqual(harmony_source_contract_errors(self.harmony), [])

    def test_harmony_source_contract_allows_format_only_changes(self):
        with tempfile.TemporaryDirectory(prefix="refract-harmony-contract-format-") as temporary:
            harmony = Path(temporary) / "harmony"
            shutil.copytree(self.harmony, harmony)
            replacements = (
                ("generated", "Text(this.row.title).font(AppTypography.rowTitle)",
                 "Text(this.row.title)\n          .font(AppTypography.rowTitle)"),
                ("generated", "Toggle({ type: ToggleType.Switch, isOn: this.row.enabled })",
                 "Toggle({\n          type: ToggleType.Switch,\n          isOn: this.row.enabled\n        })"),
                ("generated", ".id(`setting_toggle_${this.row.id}`).accessibilityText(this.row.title)",
                 ".id(`setting_toggle_${this.row.id}`)\n          .accessibilityText(this.row.title)"),
                ("model", "setEnabled(id: number, value: boolean): void {\n"
                          "    this.rows.replaceRow(id, value);",
                 "setEnabled(id: number, value: boolean): void {\n\n"
                 "      this.rows.replaceRow(id, value);"),
                ("reference", "onChange: (value: boolean): void => this.model.setEnabled(row.id, value),",
                 "onChange: (value: boolean): void =>\n"
                 "                this.model.setEnabled(row.id, value),"),
            )
            for owner, old, new in replacements:
                path = harmony / HARMONY_SOURCES[owner]
                source = path.read_text(encoding="utf-8")
                self.assertEqual(source.count(old), 1)
                path.write_text(source.replace(old, new), encoding="utf-8")
            application = harmony / HARMONY_SOURCES["application"]
            configuration = json.loads(application.read_text(encoding="utf-8"))
            configuration["app"]["products"].append({"name": "unrelated"})
            application.write_text(json.dumps(configuration, indent=4), encoding="utf-8")
            self.assertEqual(harmony_source_contract_errors(harmony), [])

    def test_harmony_source_contract_rejects_nonfinite_json_constants(self):
        for owner in ("application", "entry", "module"):
            for constant in ("NaN", "Infinity", "-Infinity"):
                with self.subTest(owner=owner, constant=constant):
                    with tempfile.TemporaryDirectory(prefix="refract-harmony-contract-json-") as temporary:
                        harmony = Path(temporary) / "harmony"
                        shutil.copytree(self.harmony, harmony)
                        self.assertEqual(harmony_source_contract_errors(harmony), [])
                        path = harmony / HARMONY_SOURCES[owner]
                        source = path.read_text(encoding="utf-8")
                        self.assertTrue(source.endswith("}\n"))
                        path.write_text(f'{source[:-2]},\n  "unrelated": {constant}\n}}\n',
                                        encoding="utf-8")
                        self.assertEqual(harmony_source_contract_errors(harmony), [
                            f"invalid {HARMONY_SOURCES[owner]} structural contract: "
                            f"non-finite JSON number is unsupported: {constant}",
                        ])

    def test_harmony_source_contract_rejects_seeded_drift(self):
        mutations = (
            ("model", None),
            ("model", ("@ObservedV2\nexport class BenchmarkSettingsModel implements SettingsModel",
                       "export class BenchmarkSettingsModel implements SettingsModel")),
            ("model", ("this.rows[index] = new SettingRow(id, previous.title, previous.subtitle, enabled);",
                       "this.rows[index].enabled = enabled;")),
            ("model", ("this.rows[index] = new SettingRow(id, previous.title, previous.subtitle, enabled);",
                       "")),
            ("model", ("BasicDataSource<SettingRow>", "BasicDataSource")),
            ("reference", ("@Require @Param model: BenchmarkSettingsModel;",
                           "@Require @Param model: SettingsModel;")),
            ("reference", ("(row: SettingRow): string => String(row.id)",
                           "(row: SettingRow): string => 'row'")),
            ("generated", ("@Trace enabled: boolean;", "enabled: boolean;")),
            ("generated", (".reuse({ reuseId: () => 'setting' })", ".reuse({ reuseId: () => 'other' })")),
            ("generated", ("../native/AppTypography", "../missing/AppTypography")),
            ("resources", ('"value": "Setting %d"', '"value": "Missing"')),
            ("application", ('"name": "release"', '"name": "profile"')),
            ("model", ("  setEnabled(id: number, value: boolean): void {\n"
                       "    this.rows.replaceRow(id, value);\n"
                       "  }", "  setEnabled(id: number, value: boolean): void {\n  }")),
            ("generated", ("      Toggle({ type: ToggleType.Switch, isOn: this.row.enabled })\n"
                           "        .onChange((enabled: boolean) => {\n"
                           "          this.model.setEnabled(this.row.id, enabled);\n"
                           "        })", "      Toggle({ type: ToggleType.Switch, isOn: false })\n"
                           "        .onChange((enabled: boolean) => {})")),
            ("generated", (".accessibilityText(this.row.title)", "")),
            ("generated", ("Text(this.row.title).font(AppTypography.rowTitle)",
                           "Text(this.row.subtitle).font(AppTypography.rowSubtitle)")),
            ("generated", (".padding({ left: 16, right: 16, top: 8, bottom: 8 })",
                           ".padding({ left: 16, right: 16, top: 32, bottom: 32 })")),
            ("reference", ("      Toggle({ type: ToggleType.Switch, isOn: this.enabled })\n"
                           "        .onChange((value: boolean): void => this.onChange(value))",
                           "      Toggle({ type: ToggleType.Switch, isOn: false })\n"
                           "        .onChange((value: boolean): void => {})")),
            ("reference", ("onChange: (value: boolean): void => this.model.setEnabled(row.id, value),",
                           "onChange: (value: boolean): void => {},")),
            ("reference", ("Text(this.subtitle)\n          .font(AppTypography.rowSubtitle)",
                           "Text(this.subtitle)\n          .font(AppTypography.rowTitle)")),
            ("reference", (".accessibilityText(this.title)", "")),
            ("reference", (".padding({ left: 16, right: 16, top: 8, bottom: 8 })",
                           ".padding({ left: 16, right: 16, top: 32, bottom: 32 })")),
            ("reference", (".alignItems(VerticalAlign.Center)", "")),
            ("reference", (".layoutWeight(1)", "")),
            ("application", ('        "compatibleSdkVersion": "26.0.0",\n'
                             '        "runtimeOS": "HarmonyOS"',
                             '        "targetSdkVersion": "26.0.0"\n'
                             '      },\n'
                             '      {\n'
                             '        "name": "unrelated",\n'
                             '        "compatibleSdkVersion": "26.0.0",\n'
                             '        "runtimeOS": "HarmonyOS"')),
            ("application", ('"buildModeSet": [{ "name": "debug" }, { "name": "release" }]',
                             '"buildModeSet": [{ "name": "debug" }],\n'
                             '    "unrelatedRelease": { "name": "release" }')),
            ("entry", ('"buildOptionSet": [\n    {\n      "name": "release",',
                       '"buildOptionSet": [],\n  "unrelatedRelease": [\n    {\n      "name": "release",')),
            ("entry", ('"buildOptionSet": [', '"buildOptionSet": [{ "name": "release" }],\n'
                       '"buildOptionSet": [')),
            ("module", ('"pages": "$profile:main_pages"', '"unrelatedPages": "$profile:main_pages"')),
            ("module", ('"deviceTypes": ["phone"],',
                        '"deviceTypes": ["phone",], // JSON5 is intentionally unsupported')),
            ("model", ("  setEnabled(id: number, value: boolean): void {\n"
                       "    this.rows.replaceRow(id, value);\n"
                       "  }", "  // setEnabled(id:number,value:boolean):void{this.rows.replaceRow(id,value);}\n"
                       "  setEnabled(id: number, value: boolean): void {}")),
            ("reference", ("LazyForEach(this.model.rows, (row: SettingRow) => {",
                           "// LazyForEach(this.model.rows, (row: SettingRow) => {\n"
                           "        ForEach([], (row: SettingRow) => {")),
        )
        for owner, mutation in mutations:
            with self.subTest(owner=owner, mutation=mutation):
                with tempfile.TemporaryDirectory(prefix="refract-harmony-contract-") as temporary:
                    bench = Path(temporary) / "bench"
                    harmony = bench / "harmony"
                    shutil.copytree(self.harmony, harmony)
                    self.assertEqual(harmony_source_contract_errors(harmony), [])
                    path = harmony / HARMONY_SOURCES[owner]
                    if mutation is None:
                        path.unlink()
                    else:
                        old, new = mutation
                        source = path.read_text(encoding="utf-8")
                        self.assertEqual(source.count(old), 1)
                        path.write_text(source.replace(old, new), encoding="utf-8")
                    self.assertNotEqual(harmony_source_contract_errors(harmony), [])

    def test_report_contract_requires_all_scenarios_and_explicit_target_label(self):
        source = (self.root / "bench/common/paired_report.py").read_text(encoding="utf-8")
        self.assertIn("MINIMUM_ITERATIONS = 30", source)
        for scenario in ("startup", "scroll", "stateUpdate"):
            self.assertIn(f'"{scenario}"', source)
        self.assertIn('"SIMULATOR"', source)
        self.assertIn('"EMULATOR"', source)
        self.assertIn('"DEVICE"', source)


if __name__ == "__main__":
    unittest.main()
