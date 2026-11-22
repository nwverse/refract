import Foundation
import Testing
import RefractIR
import RefractMapping
import RefractFrontend
import RefractGolden
@testable import RefractCompose
import RefractArkUI

private let measurementMapping = Mapping(
    android: PlatformMapping(
        imports: [NativeImport(module: "example.design.AppTypography", symbols: ["AppTypography"])],
        tokens: TokenSet(font: ["DesignTypography.rowTitle": "AppTypography.rowTitle"])
    ),
    harmonyOS: PlatformMapping(
        imports: [NativeImport(module: "example.design", symbols: ["AppTypography"])],
        tokens: TokenSet(font: ["DesignTypography.rowTitle": "AppTypography.rowTitle"])
    )
)

@Test func nativeModifierPreservesAllTypedPlatformBranches() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Measurement: View {
        var body: some View {
            refractView(
                ios: { Text(verbatim: "Title").accessibilityLabel("Accessible title") },
                android: { Text(verbatim: "Title").refractNativeModifier(.testTag("row_title"), .contentDescription("Accessible title")) },
                harmonyOS: { Text(verbatim: "Title").accessibilityLabel("Accessible title").refractNativeModifier(.testTag("row_title")) }
            )
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .platformView(alternatives, _) = unit.module.screens[0].body,
          case let .text(_, iosModifiers, _) = alternatives.ios[0],
          case let .nativeModifier(_, operations, _) = alternatives.android[0] else {
        Issue.record("Expected explicit native/iOS alternatives")
        return
    }
    #expect(iosModifiers.map(\.name) == ["accessibilityLabel"])
    #expect(operations.count == 2)
    let kotlin = try ComposeBackend().generate(module: unit.module)
    #expect(kotlin.contains(".testTag(\"row_title\").semantics { contentDescription = \"Accessible title\" }"))
    #expect(!kotlin.contains("accessibilityText"))
    let ark = try ArkUIBackend().generate(module: unit.module)
    #expect(ark.contains(".accessibilityText('Accessible title')"))
    #expect(ark.contains(".id('row_title')"))
    #expect(!ark.contains("contentDescription"))
}

@Test func nativeModifierRejectsUnknownAndIllTypedOperations() {
    let unknown = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View { var body: some View { Text(verbatim: "Title").refractNativeModifier(.eraseToAnyModifier()) } }
    """))
    #expect(unknown.diagnostics.map(\.code) == ["RFNATIVE004"])
    #expect(unknown.diagnostics[0].location != nil)
    let untyped = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View { var body: some View { Text(verbatim: "Title").refractNativeModifier(.testTag(42)) } }
    """))
    #expect(untyped.diagnostics.map(\.code) == ["RFNATIVE004"])
    let receiver = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View { var body: some View { List { Text(verbatim: "Title") }.refractNativeModifier(.retainCallback(identity: "row")) } }
    """))
    #expect(receiver.diagnostics.map(\.code) == ["RFNATIVE004"])
}

@Test func nativeModifierRejectsForgedIOSSemanticsOnOtherTargets() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Invalid", body: .text(Expression(.verbatimText("Title")), modifiers: [
            Modifier(name: "accessibilityLabel", arguments: [Expression(.stringLiteral("Title"))], argumentLabels: [nil]),
        ], location: nil)),
    ])
    #expect(throws: Diagnostic.self) { try ComposeBackend().generate(module: module) }
}

@Test func retainedModelActionUsesAllCapturedIdentityKeys() throws {
    let action = StateAction.modelMethod(model: "model", name: "refresh", arguments: [
        ActionArgument(label: nil, value: Expression(.reference("row.id"))),
    ])
    let node = ViewNode.button(
        label: .text(Expression(.verbatimText("Refresh")), modifiers: [], location: nil),
        action: action, modifiers: [], location: nil)
    let module = Module(sourceFile: "Input.swift", screens: [Screen(name: "Retained", body: node)],
                        itemTypes: [ItemType(name: "SettingRow", identity: ItemProperty(name: "id", type: .int), properties: [])])
    var context = ComposeBackend.Context(module: module, mapping: .empty)
    context.retainedItem = ("row", "SettingRow")
    var writer = KotlinWriter()
    try ComposeNativeModifier().emit(node, operations: [
        NativeModifier(operation: .retainCallback(identity: "settings.refresh")),
    ], isRoot: false, into: &writer, context: &context)
    #expect(writer.text.contains("remember(model, row.id, \"settings.refresh\")"))
    #expect(writer.text.contains("Button(onClick = onClick"))
}

@Test func childItemToggleUsesDeclaredInputReceiver() throws {
    let fixture = FixtureCase(name: "child-view-layout-priority", status: .ready,
        input: try String(contentsOfFile: "Fixtures/child-view-layout-priority/Input.swift", encoding: .utf8),
        mapping: try String(contentsOfFile: "Fixtures/child-view-layout-priority/refract.json", encoding: .utf8),
        expectedKotlin: nil, expectedArkTS: nil, expectedDiagnostics: nil)
    let result = try GoldenRunner.generate(fixture)
    #expect(result.diagnostics.isEmpty)
    let kotlin = try #require(result.kotlin)
    #expect(kotlin.contains("checked = row.enabled"))
    #expect(kotlin.contains("settings.setEnabled(row.id, enabled)"))
    let ark = try #require(result.arkTS)
    #expect(ark.contains("isOn: this.row.enabled"), Comment(rawValue: ark))
    #expect(ark.contains("this.settings.setEnabled(this.row.id, enabled);"), Comment(rawValue: ark))
    #expect(ark.contains(".id(`setting_toggle_${this.row.id}`)"))
    #expect(ark.contains("LazyForEach(this.model.rows, (row: ChildSettingItem) =>"))
}

@Test func ordinaryListItemToggleRetainsLocalReceiver() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol ListModel: RefractModel {
        var rows: [ListRow] { get }
        func setEnabled(_ id: Int, value: Bool)
    }
    struct ListRow: Identifiable { let id: Int; let title: String; let enabled: Bool }
    struct UnusedChild: View {
        let row: ListRow
        var body: some View { Text(row.title) }
    }
    struct ListScreen: View {
        let model: ListModel
        var body: some View {
            List(model.rows) { row in
                Toggle("settings.item\\(row.id)", isOn: Binding(
                    get: { row.enabled },
                    set: { value in model.setEnabled(row.id, value: value) }
                ))
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let mapping = try Mapping.load(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/interop-native-measurement/refract.json"))
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("isOn: row.enabled"), Comment(rawValue: ark))
    #expect(ark.contains("this.model.setEnabled(row.id, enabled);"))
    #expect(!ark.contains("isOn: this.row.enabled"))
    #expect(!ark.contains("setEnabled(this.row.id"))
}

@Test func retainedItemToggleUsesMergedTypedAction() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel {
        var rows: [Row] { get }
        func setEnabled(_ id: Int, value: Bool)
    }
    struct Row: Identifiable { let id: Int; let title: String; let enabled: Bool }
    struct Screen: View {
        let model: Model
        var body: some View {
            List(model.rows) { row in
                Toggle("settings.item\\(row.id)", isOn: Binding(
                    get: { row.enabled },
                    set: { value in model.setEnabled(row.id, value: value) }
                ))
                .refractNativeModifier(.testTag("settings_toggle"), .contentDescription(row.title), .retainCallback(identity: "settings.setEnabled"))
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let mapping = try Mapping.load(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/interop-native-measurement/refract.json"))
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("remember(model, row.id)"))
    #expect(kotlin.contains("onCheckedChange = onCheckedChange"))
    #expect(kotlin.contains("modifier = Modifier.testTag(\"settings_toggle\").semantics { contentDescription = row.title }"))
    let diagnostic = #expect(throws: Diagnostic.self) {
        try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    }
    #expect(diagnostic?.code == "RFNATIVE004")
}

@Test func nativeModifierRejectsComputedAndMisplacedRetention() {
    let computed = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View { var body: some View { Text(verbatim: "Title").refractNativeModifier(.testTag("row_\\(unknown)")) } }
    """))
    #expect(computed.diagnostics.contains { $0.code == "RFNATIVE004" })
    let localState = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View {
        @State private var enabled: Bool = false
        var body: some View { Toggle("settings.enabled", isOn: $enabled).refractNativeModifier(.retainCallback(identity: "settings.enabled")) }
    }
    """))
    #expect(localState.diagnostics.map(\.code) == ["RFNATIVE004"])
    let text = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View { var body: some View { Text(verbatim: "Title").refractNativeModifier(.retainCallback(identity: "row")) } }
    """))
    #expect(text.diagnostics.map(\.code) == ["RFNATIVE004"])
}

@Test(arguments: [
    ".contentType(\"setting\", \"other\")",
    ".contentType(identity)",
    ".contentType(\"Setting\")",
    ".contentType(\"setting-row\")",
    ".contentType(\"\")",
    ".contentType(\"setting\").refractNativeModifier(.contentType(\"setting\"))",
])
func rowContentTypeRejectsInvalidOrDuplicateDeclarations(_ operation: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel { var rows: [Row] { get } }
    struct Row: Identifiable { let id: Int; let title: String }
    struct SettingRow: View {
        let model: Model
        let row: Row
        var body: some View { Text(row.title) }
    }
    struct Page: View {
        let model: Model
        var body: some View {
            List {
                ForEach(model.rows) { row in
                    SettingRow(model: model, row: row)
                        .refractNativeModifier(\(operation))
                }
            }
        }
    }
    """))
    #expect(unit.diagnostics.contains { $0.code == "RFNATIVE004" })
    #expect(unit.hasErrors)
    #expect(unit.module.screens.map(\.name) == ["SettingRow"])
}

@Test(arguments: ["Toggle", "Text", "HStack"])
func rowContentTypeDoesNotFallThroughToToggleOrWrapper(_ receiver: String) {
    let body: String
    switch receiver {
    case "Toggle":
        body = "Toggle(\"settings.enabled\", isOn: $enabled).refractNativeModifier(.contentType(\"setting\"))"
    case "Text":
        body = "Text(verbatim: \"Title\").refractNativeModifier(.contentType(\"setting\"))"
    default:
        body = "HStack { Text(verbatim: \"Title\") }.refractNativeModifier(.contentType(\"setting\"))"
    }
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View {
        @State private var enabled: Bool = false
        var body: some View { \(body) }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE004"])
    #expect(!unit.diagnostics.contains { $0.message.contains("callback retention") })
    #expect(unit.module.screens.isEmpty)
}

@Test func invalidToggleContentTypeCannotUseRetainedCallbackFallback() throws {
    let toggle = ViewNode.toggle(title: Expression(.stringLiteral("Enabled")),
                                 value: Expression(.valueProperty(.state("enabled"))), modifiers: [],
                                 nativeModifiers: [NativeModifier(operation: .contentType("setting"))],
                                 labelsHidden: true, location: nil)
    let module = Module(sourceFile: "Input.swift", screens: [Screen(name: "Invalid", body: toggle)])
    let compose = #expect(throws: Diagnostic.self) { try ComposeBackend().generate(module: module) }
    let ark = #expect(throws: Diagnostic.self) { try ArkUIBackend().generate(module: module) }
    #expect(compose?.code == "RFNATIVE004" && compose?.message.contains("not its Toggle") == true)
    #expect(ark?.code == "RFNATIVE004" && ark?.message.contains("not its Toggle") == true)
}

@Test func measurementStringsPreserveTypedItemInterpolation() throws {
    let fixture = try CorpusLoader.load(repository: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        .first { $0.name == "child-view-layout-priority" }
    let result = try GoldenRunner.generate(try #require(fixture))
    #expect(GoldenRunner.differences(for: try #require(fixture), result: result) == [])
    #expect(result.kotlin?.contains("modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).testTag(\"setting_row_${row.id}\")") == true)
    #expect(result.kotlin?.contains("Column(modifier = Modifier.weight(1f))") == true)
    #expect(result.kotlin?.contains("Modifier.testTag(\"setting_toggle_${row.id}\")") == true)
    #expect(result.arkTS?.contains(".id(`setting_toggle_${this.row.id}`).accessibilityText(this.row.title)") == true)
    #expect(result.arkTS?.contains("Toggle({ type: ToggleType.Switch, isOn: this.row.enabled })") == true)
    #expect(result.arkTS?.contains("ChildSettingRow({ settings: this.model, row: row })\n          .reuse({ reuseId: () => 'setting' })") == true)
    #expect(result.kotlin?.contains("contentType = { \"setting\" }") == true)
    #expect(result.kotlin?.contains("Arrangement.SpaceBetween") == false)
    #expect(result.arkTS?.contains("justifyContent(FlexAlign.SpaceBetween)") == false)
    #expect(result.arkTS?.contains(".alignItems(VerticalAlign.Center)\n    .id(`setting_row_${this.row.id}`)") == true)
}

@Test func measurementStringsRejectUntypedInterpolation() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Invalid: View {
        var body: some View {
            Text(verbatim: "Title").refractNativeModifier(.testTag("row_\\(unknown)"))
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE004"])
    #expect(unit.diagnostics[0].location != nil)
}

@Test func directionalPaddingAndTypographyKeepNativeRowShape() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct RowShape: View {
        var body: some View {
            Text(verbatim: "Title").font(DesignTypography.rowTitle).padding(horizontal: 16, vertical: 8)
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: measurementMapping)
    #expect(kotlin.contains(".padding(horizontal = 16.dp, vertical = 8.dp)"))
    #expect(kotlin.contains("style = AppTypography.rowTitle"))
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: measurementMapping)
    #expect(ark.contains(".padding({ left: 16, right: 16, top: 8, bottom: 8 })"))
    #expect(ark.contains(".font(AppTypography.rowTitle)"))
}
