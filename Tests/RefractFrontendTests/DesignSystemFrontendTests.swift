import Foundation
import Testing
import RefractIR
import RefractMapping
@testable import RefractFrontend

@Test func mappedComponentKeepsAllModifiersInSourceOrder() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let input = try String(contentsOf: root.appendingPathComponent("Fixtures/mapping/brand-a/Input.swift"), encoding: .utf8)
    let mapping = try Mapping.load(contentsOf: root.appendingPathComponent("Fixtures/mapping/brand-a/refract.json"))
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input), mapping: mapping)
    #expect(unit.diagnostics.isEmpty)
    guard case let .component(component, _)? = unit.module.screens.first?.body else {
        Issue.record("Expected a mapped component root")
        return
    }
    #expect(component.modifiers.map(\.name) == ["padding", "background"])
    #expect(component.children.count == 1)
    guard case let .reference(token)? = component.modifiers.first?.arguments.first?.value else {
        Issue.record("Expected a typed token reference")
        return
    }
    #expect(token == "DesignSpacing.medium")
}
