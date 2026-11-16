import Foundation
import Testing
@testable import RefractArkUI
@testable import RefractFrontend
import RefractIR

@Test func arkUIMatchesIdentifiedListGolden() throws {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/v0-identified-list")
    let input = try String(contentsOf: directory.appendingPathComponent("Input.swift"), encoding: .utf8)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input))
    #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
    let actual = try ArkUIBackend().generate(module: unit.module)
    let expected = try String(contentsOf: directory.appendingPathComponent("Expected.ets"), encoding: .utf8)
    #expect(actual == expected)
    #expect(!actual.contains("Array<Item>"))
    #expect(!actual.contains("index"))
}

@Test func frontendRejectsListWithoutDeclaredItemIdentity() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol ListModel: RefractModel { var items: [MissingItem] { get } }
    struct Missing: View {
      let model: ListModel
      var body: some View { List(model.items) { item in Text(item.title) } }
    }
    """))
    #expect(unit.diagnostics.map(\.code).contains("model.invalid_property"))
}

private func identifiedListSource(itemFields: String = "let id: String\n  let title: String",
                                  row: String = "Text(item.title)",
                                  identityArgument: String = "",
                                  conformance: String = "Identifiable") -> SourceFile {
    SourceFile(path: "Input.swift", contents: """
struct SettingItem: \(conformance) {
  \(itemFields)
}

protocol SettingsListModel: RefractModel {
  var items: [SettingItem] { get }
}

struct IdentifiedList: View {
  let model: SettingsListModel
  var body: some View {
    List(model.items\(identityArgument)) { item in
      \(row)
    }
  }
}
""")
}

@Test func frontendRejectsUnsupportedListIdentityAndDroppedRows() {
    let booleanIdentity = Frontend.parse(identifiedListSource(itemFields: "let id: Bool\n  let title: String"))
    #expect(booleanIdentity.diagnostics.map(\.code) == ["RFLIST001", "model.invalid_property", "state.invalid_declaration"])
    #expect(booleanIdentity.diagnostics.first?.location?.line == 2)
    #expect(booleanIdentity.diagnostics.first?.location?.column == 3)

    let computedIdentity = Frontend.parse(identifiedListSource(itemFields: "var id: String { title }\n  let title: String"))
    #expect(computedIdentity.diagnostics.map(\.code) == ["RFLIST001", "model.invalid_property", "state.invalid_declaration"])

    let implicitIdentity = Frontend.parse(identifiedListSource(identityArgument: ", id: \\.self"))
    #expect(implicitIdentity.diagnostics.map(\.code) == ["RFLIST002"])

    let rows = Frontend.parse(identifiedListSource(row: "Text(item.title)\n        Text(item.id)"))
    #expect(rows.diagnostics.map(\.code) == ["RFLIST003"])

    let hashableItem = Frontend.parse(identifiedListSource(conformance: "Hashable, Identifiable"))
    #expect(hashableItem.diagnostics.isEmpty)
}

@Test func frontendValidatesTypedItemScope() throws {
    let unknown = Frontend.parse(identifiedListSource(row: "Text(item.missing)"))
    #expect(unknown.diagnostics.map(\.code) == ["RFSEM001", "RFSEM001", "RFSEM001", "unsupportedText"])

    let wrongType = Frontend.parse(identifiedListSource(row: "Text(item.id)"))
    #expect(wrongType.diagnostics.isEmpty)
    #expect(try ArkUIBackend().generate(module: wrongType.module).contains("Text(item.id)"))

    let integerText = Frontend.parse(identifiedListSource(itemFields: "let id: Int\n  let title: String",
                                                        row: "Text(item.id)"))
    #expect(integerText.diagnostics.isEmpty, Comment(rawValue: integerText.diagnostics.map(\.rendered).joined(separator: "\n")))

    let collectionText = Frontend.parse(identifiedListSource(row: "Text(model.items)"))
    #expect(collectionText.diagnostics.map(\.code) == ["RFSEM001", "unsupportedText"])

    let numeric = Frontend.parse(identifiedListSource(itemFields: "let id: Int\n    let title: String"))
    #expect(numeric.diagnostics.isEmpty)
    let output = try ArkUIBackend().generate(module: numeric.module)
    #expect(output.contains("(item: SettingItem): string => String(item.id)"))
    #expect(output.contains("items: BasicDataSource<SettingItem>;"))
    #expect(!output.contains("@Monitor"))
    #expect(!output.contains("Array<SettingItem>"))
}
