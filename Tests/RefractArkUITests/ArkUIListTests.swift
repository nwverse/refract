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
