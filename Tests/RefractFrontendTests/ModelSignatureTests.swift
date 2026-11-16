import Testing
@testable import RefractFrontend
import RefractIR

@Test func modelRejectsExternalLabelSignatureCollision() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SettingsModel: RefractModel {
        var title: String { get }
        func update(_ value: Bool)
        func update(with value: Bool)
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["model.duplicate_member"])
    #expect(unit.module.models.isEmpty)
    #expect(unit.hasErrors)
}

@Test func modelRejectsDuplicatePropertyAndActionName() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SettingsModel: RefractModel {
        var update: Bool { get }
        func update(_ value: Bool)
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["model.duplicate_member"])
    #expect(unit.module.models.isEmpty)
}

@Test func modelPreservesUniqueExternalArgumentLabels() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SettingsModel: RefractModel {
        func update(_ value: Bool)
        func rename(to value: String)
        func update(with value: Bool, immediately: Bool)
        func update(with value: String)
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let model = try #require(unit.module.models.first)
    #expect(model.actions.map(\.name) == ["update", "rename", "update", "update"])
    #expect(model.actions[2].parameters.map(\.externalName) == ["with", "immediately"])
}
