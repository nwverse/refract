import Testing
@testable import RefractFrontend
import RefractIR

@Test func frontendCapturesModelProtocolReadAndAction() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SettingsModel: RefractModel {
        var title: String { get }
        func setEnabled(_ value: Bool)
    }
    struct Settings: View {
        let model: SettingsModel
        var body: some View {
            VStack {
                Text(model.title)
                Button(verbatim: "Disable") { model.setEnabled(false) }
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let contract = try #require(unit.module.models.first)
    #expect(contract.properties.map(\.name) == ["title"])
    #expect(contract.actions.first?.parameters.first?.externalName == nil)
    #expect(contract.actions.first?.parameters.first?.localName == "value")
    let screen = try #require(unit.module.screens.first)
    guard case let .model(reference, _) = screen.states.first,
          case let .stack(_, children, _, _) = screen.body,
          case let .text(text, _, _) = children[0],
          case let .button(_, action, _, _) = children[1] else {
        Issue.record("Expected a model-backed screen")
        return
    }
    #expect(reference.protocolName == "SettingsModel")
    #expect(text.value == .valueProperty(.model(model: "model", property: "title")))
    guard case let .modelMethod(model, name, arguments) = action else {
        Issue.record("Expected a model action")
        return
    }
    #expect(model == "model")
    #expect(name == "setEnabled")
    #expect(arguments.count == 1)
    #expect(arguments[0].label == nil)
    #expect(arguments[0].value.value == .boolLiteral(false))
}

@Test func frontendPreservesExternalModelActionLabels() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SettingsModel: RefractModel {
        func rename(to value: String)
    }
    struct Settings: View {
        let model: SettingsModel
        var body: some View { Button(verbatim: "Rename") { model.rename(to: "New") } }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .button(_, action, _, _) = unit.module.screens.first?.body,
          case let .modelMethod(_, _, arguments) = action else {
        Issue.record("Expected a labeled model action")
        return
    }
    #expect(arguments.first?.label == "to")
    #expect(unit.module.models.first?.actions.first?.parameters.first?.localName == "value")
}


@Test(arguments: [
    ("var title: String { get set }", "model.invalid_property"),
    ("func refresh() async", "model.invalid_action"),
    ("associatedtype Item", "model.unsupported_requirement"),
])
func frontendRejectsInvalidModelRequirements(_ requirement: String, _ code: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SettingsModel: RefractModel {
        \(requirement)
    }
    """))
    #expect(unit.diagnostics.first?.code == code)
    #expect(unit.module.models.isEmpty)
}
