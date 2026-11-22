import Foundation
import Testing
import RefractFrontend
import RefractGolden
import RefractIR

private let horizontalRepository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Test func horizontalSectionIRRetainsModelAndItemIdentity() throws {
    let source = try String(contentsOf: horizontalRepository.appendingPathComponent("Fixtures/horizontal-sections/Input.swift"), encoding: .utf8)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source))
    #expect(unit.diagnostics.isEmpty)
    guard case let .list(children, _, _) = unit.module.screens[0].body,
          case let .horizontalSections(sections, _) = children[0] else {
        Issue.record("Expected horizontal sections IR")
        return
    }
    #expect(sections.modelType == "GalleryModel")
    #expect(sections.sectionType == "GallerySection")
    #expect(sections.sectionKey == "id")
    #expect(sections.rows.property == "items")
    #expect(sections.rows.itemType == "GalleryItem")
    #expect(sections.rows.key == "id")
    #expect(sections.collection.value == .valueProperty(.model(model: "model", property: "sections")))
    let gallery = unit.module.models.first { $0.name == "GalleryModel" }
    #expect(gallery?.properties.first(where: { $0.name == "sections" })?.collection?.itemType == "GallerySection")
    #expect(gallery?.properties.first(where: { $0.name == "sections" })?.collection?.key == "id")
}

@Test func horizontalRowShadowsSameNamedDeclaredItemInput() throws {
    let directory = horizontalRepository.appendingPathComponent("Fixtures/horizontal-sections-item-shadow")
    let fixture = FixtureCase(name: "horizontal-sections-item-shadow", status: .ready,
        input: try String(contentsOf: directory.appendingPathComponent("Input.swift"), encoding: .utf8),
        mapping: try String(contentsOf: directory.appendingPathComponent("refract.json"), encoding: .utf8),
        expectedKotlin: nil, expectedArkTS: nil, expectedDiagnostics: nil)
    let result = try GoldenRunner.generate(fixture)
    #expect(result.diagnostics.isEmpty)
    let kotlin = try #require(result.kotlin)
    #expect(kotlin.contains("items = section.items"))
    #expect(kotlin.contains("checked = item.enabled"))
    #expect(kotlin.contains("model.setEnabled(item.id, enabled)"))
    let ark = try #require(result.arkTS)
    #expect(ark.contains("@Param @Require public var item: ShadowGalleryItem"))
    #expect(ark.contains("ForEach(section.items, (item: ShadowGalleryItem) => {"))
    #expect(ark.contains("isOn: item.enabled"), Comment(rawValue: ark))
    #expect(ark.contains("this.model.setEnabled(item.id, enabled);"), Comment(rawValue: ark))
    #expect(!ark.contains("isOn: this.item.enabled"))
    #expect(!ark.contains("setEnabled(this.item.id"))
}
