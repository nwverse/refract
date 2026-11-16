import Foundation
import Testing
import RefractIR
import RefractMapping
@testable import RefractFrontend
import RefractCompose
import RefractArkUI

private let childSource = """
protocol RowsModel: RefractModel {
    var rows: [ChildRow] { get }
    func setEnabled(_ id: Int, value: Bool)
}
struct ChildRow: Identifiable {
    let id: Int
    let title: String
    let enabled: Bool
}
struct ChildSettingRow: View {
    let settings: RowsModel
    let row: ChildRow
    var body: some View {
        HStack(alignment: .center) {
            VStack {
                Text(row.title)
            }.layoutPriority(1)
            refractView(
                ios: { Text(row.title).accessibilityLabel(row.title) },
                android: {
                    Toggle("settings.item\\(row.id)", isOn: Binding(
                        get: { row.enabled },
                        set: { value in settings.setEnabled(row.id, value: value) }
                    )).refractNativeModifier(.testTag("setting_toggle"), .retainCallback(identity: "settings.setEnabled"))
                },
                harmonyOS: { Toggle("settings.item\\(row.id)", isOn: Binding(
                    get: { row.enabled },
                    set: { value in settings.setEnabled(row.id, value: value) }
                )) }
            )
        }
    }
}
struct ChildSettings: View {
    let model: RowsModel
    var body: some View {
        List(model.rows) { row in
            ChildSettingRow(settings: model, row: row)
        }
    }
}
"""

@Test func childViewAndHStackPriorityLowerThroughTypedIR() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: childSource))
    #expect(unit.diagnostics.isEmpty)
    let child = try #require(unit.module.screens.first { $0.name == "ChildSettingRow" })
    #expect(child.parameters.map(\.itemType) == ["ChildRow"])
    guard case let .list(listChildren, _, _) = try #require(unit.module.screens.last).body,
          case let .forEach(items, _) = listChildren[0],
          case let .child(call, _) = items.content else {
        Issue.record("Expected a typed child call in the dynamic list")
        return
    }
    #expect(call.name == "ChildSettingRow")
    #expect(call.models.map(\.label) == ["settings"] && call.models.map(\.expression) == ["model"])
    #expect(call.item?.label == "row" && call.item?.expression == "row")
    let mapping = try Mapping.load(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/interop-native-measurement/refract.json"))
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("ChildSettingRow(settings = model, row = row)"))
    #expect(kotlin.contains("Column(modifier = Modifier.weight(1f))"))
    #expect(kotlin.contains("remember(settings, row.id)"))
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("@Param @Require public var row: ChildRow"))
    #expect(ark.contains("ChildSettingRow({ settings: this.model, row: row })"))
    #expect(ark.contains("}.layoutWeight(1)"))
}

@Test(arguments: [
    "ChildSettingRow(model, row)",
    "ChildSettingRow(settings: model)",
    "ChildSettingRow(settings: model, row: model)",
    "ChildSettingRow(settings: row, row: row)",
    "ChildSettingRow(settings: model, row: row) { Text(row.title) }",
])
func childViewRejectsInvalidArguments(expression: String) {
    let source = childSource.replacingOccurrences(of: "ChildSettingRow(settings: model, row: row)\n", with: expression + "\n")
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source))
    #expect(unit.diagnostics.contains { $0.code == "RFVIEW006" })
}

@Test func childViewRejectsRecursion() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Recursive: View { var body: some View { Recursive() } }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFVIEW006"])
}

@Test func childViewRejectsIndirectRecursion() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct First: View { var body: some View { Second() } }
    struct Second: View { var body: some View { First() } }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFVIEW006"])
    #expect(unit.diagnostics[0].message.contains("First -> Second -> First"))
}

@Test func consecutiveChildViewsKeepLocalInputsAndCallerItemAlias() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel { var rows: [Row] { get } }
    protocol OtherModel: RefractModel { var title: String { get } }
    struct Row: Identifiable { let id: Int; let title: String }
    struct First: View {
        let setting: Row
        let model: Model
        let secondary: OtherModel
        var body: some View { Text(setting.title) }
    }
    struct Second: View {
        let item: Row
        let model: Model
        var body: some View { Text(item.title) }
    }
    struct Parent: View {
        let model: Model
        let other: OtherModel
        var body: some View {
            List(model.rows) { row in
                First(setting: row, model: model, secondary: other)
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
    #expect(unit.module.screens.map(\.name) == ["First", "Second", "Parent"])
    #expect(unit.module.screens[0].parameters.map(\.name) == ["setting"])
    #expect(unit.module.screens[0].states.count == 2)
    #expect(unit.module.screens[1].parameters.map(\.name) == ["item"])
    guard case let .list(children, _, _) = unit.module.screens[2].body,
          case let .forEach(items, _) = children[0],
          case let .child(first, _) = items.content else {
        Issue.record("Expected a typed child call with an item alias")
        return
    }
    #expect(first.item == ChildView.Argument(label: "setting", expression: "row"))
    #expect(first.models.map(\.label) == ["model", "secondary"])
    #expect(first.models.map(\.expression) == ["model", "other"])
    #expect(first.arguments.map(\.label) == ["setting", "model", "secondary"])
    let kotlin = try ComposeBackend().generate(module: unit.module)
    #expect(kotlin.contains("First(setting = row, model = model, secondary = other)"), Comment(rawValue: kotlin))
    #expect(kotlin.contains("text = setting.title"))
    #expect(kotlin.contains("text = item.title"))
    let ark = try ArkUIBackend().generate(module: unit.module)
    #expect(ark.contains("First({ setting: row, model: this.model, secondary: this.other })"))
}

@Test func typedInputParserDoesNotAccumulateDuplicateScalarParameters() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct First: View {
        let title: String
        var body: some View { Text(title) }
    }
    struct Second: View {
        let title: String
        var body: some View { Text(title) }
    }
    """))
    #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
    #expect(unit.module.screens.map { $0.parameters.map(\.name) } == [["title"], ["title"]])
}

@Test(arguments: [
    "VStack { Text(verbatim: \"Bad\").layoutPriority(1) }",
    "HStack { VStack { Text(verbatim: \"Bad\").layoutPriority(1) } }",
    "HStack { Text(verbatim: \"Bad\").layoutPriority(1.5) }",
    "HStack { Text(verbatim: \"Bad\").layoutPriority(0.5) }",
    "HStack { Text(verbatim: \"Bad\").layoutPriority(2) }",
    "HStack { Text(verbatim: \"Bad\").layoutPriority(1).layoutPriority(1) }",
])
func hStackPriorityRejectsUnsupportedForms(expression: String) throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Layout: View { var body: some View { \(expression) } }
    """))
    #expect(unit.diagnostics.isEmpty)
    #expect(throws: Diagnostic.self) { try ComposeBackend().generate(module: unit.module) }
    #expect(throws: Diagnostic.self) { try ArkUIBackend().generate(module: unit.module) }
}
