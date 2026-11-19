import Foundation
import Testing
import RefractFrontend
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
