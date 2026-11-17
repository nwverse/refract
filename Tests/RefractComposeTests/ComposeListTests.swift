import Foundation
import Testing
import RefractFrontend
import RefractIR
@testable import RefractCompose

@Test func composeMatchesHandWrittenIdentifiedListGolden() throws {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/v0-identified-list")
    let input = try String(contentsOf: directory.appendingPathComponent("Input.swift"), encoding: .utf8)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input))
    #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
    let output = try ComposeBackend().generate(module: unit.module)
    let expected = try String(contentsOf: directory.appendingPathComponent("Expected.kt"), encoding: .utf8)
    #expect(output == expected)
    #expect(output.contains("State<List<SettingItem>>"))
    #expect(output.contains("key = { item -> item.id }"))
    #expect(output.contains("contentType = { \"SettingItem\" }"))
    #expect(output.contains("Text(text = item.title)"))
    #expect(!output.contains("Column(modifier = modifier).verticalScroll"))
    #expect(!output.contains("ForEach"))
    #expect(!output.contains("index"))
    #expect(!output.contains("import refract."))
}

@Test func composeRejectsCollectionWithoutResolvedObservableModel() throws {
    let item = ItemType(name: "SettingItem",
                        identity: ItemProperty(name: "id", type: .string),
                        properties: [ItemProperty(name: "id", type: .string)])
    let rows = ListItems(collection: Expression(.reference("items")), itemName: "item",
                         itemType: "SettingItem", keyType: .string,
                         content: .text(Expression(.reference("item.title")), modifiers: [], location: nil))
    let module = Module(sourceFile: "Input.swift",
                        screens: [Screen(name: "InvalidList", states: [
                            .model(ModelReference(propertyName: "model", protocolName: "ListModel"), location: nil),
                        ], body: .list(
                            children: [.forEach(rows, location: nil)], modifiers: [], location: nil))],
                        itemTypes: [item])
    let diagnostic = #expect(throws: Diagnostic.self) {
        try ComposeBackend().generate(module: module)
    }
    #expect(diagnostic?.code == "RFLIST001")
}

@Test func composeLowersIntegerItemIdentityWithoutIndexSubstitution() throws {
    let item = ItemType(name: "IntItem", identity: ItemProperty(name: "id", type: .int),
                        properties: [ItemProperty(name: "id", type: .int),
                                     ItemProperty(name: "title", type: .string)])
    let collection = ModelCollection(itemType: "IntItem", keyType: .int)
    let model = ModelProtocol(name: "ListModel", properties: [
        ModelProperty(name: "items", type: .string, collection: collection),
    ])
    let rows = ListItems(collection: Expression(.valueProperty(.model(model: "model", property: "items"))),
                         itemName: "item", itemType: "IntItem", keyType: .int,
                         content: .text(Expression(.reference("item.title")), modifiers: [], location: nil),
                         modelType: "ListModel")
    let module = Module(sourceFile: "Input.swift",
                        screens: [Screen(name: "IntList", states: [
                            .model(ModelReference(propertyName: "model", protocolName: "ListModel"), location: nil),
                        ], body: .list(children: [.forEach(rows, location: nil)], modifiers: [], location: nil))],
                        models: [model], itemTypes: [item])
    let output = try ComposeBackend().generate(module: module)
    #expect(output.contains("State<List<IntItem>>"))
    #expect(output.contains("key = { item -> item.id }"))
    #expect(!output.contains("String(item.id)"))
    #expect(!output.contains("index"))
}
