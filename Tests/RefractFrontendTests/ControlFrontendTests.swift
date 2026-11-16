import Testing
@testable import RefractFrontend
import RefractIR

@Test(arguments: [
    ("@State private var isEnabled: Bool = false", ValueProperty.state("isEnabled")),
    ("@Binding var isEnabled: Bool", ValueProperty.binding("isEnabled")),
])
func frontendParsesOnlyDeclaredBoolToggleProjection(_ declaration: String, _ expected: ValueProperty) throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct ToggleRow: View {
        \(declaration)
        var body: some View { Toggle("settings.enabled", isOn: $isEnabled) }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .toggle(title, value, _, _) = unit.module.screens.first?.body else {
        Issue.record("Expected a typed toggle")
        return
    }
    #expect(title.value == .stringKey("settings.enabled"))
    #expect(value.value == .valueProperty(expected))
}

@Test func frontendParsesTypedItemToggleBinding() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SettingsModel: RefractModel {
        var rows: [SettingRow] { get }
        func setEnabled(_ id: Int, value: Bool)
    }
    struct SettingRow: Identifiable { let id: Int; let title: String; let enabled: Bool }
    struct ItemToggle: View {
        let model: SettingsModel
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
    guard case let .list(children, _, _) = unit.module.screens.first?.body,
          case let .forEach(items, _) = children.first,
          case let .toggle(title, value, _, _) = items.content,
          case let .valueProperty(.itemBinding(binding)) = value.value else {
        Issue.record("Expected a typed item toggle")
        return
    }
    guard case let .localizedText(localized) = title.value else {
        Issue.record("Expected a localized item title")
        return
    }
    #expect(localized.key == "settings.item")
    #expect(localized.arguments.map(\.value) == [.reference("row.id")])
    #expect(localized.arguments.map(\.type) == [.int])
    #expect(binding == ItemBinding(model: "model", item: "row", property: "enabled", key: "id", action: "setEnabled"))
}

@Test(arguments: [
    ("get: { row.title }", "{ model.setEnabled(row.id, value: $0) }"),
    ("get: { other.enabled }", "{ model.setEnabled(row.id, value: $0) }"),
    ("get: { row.enabled }", "{ model.setEnabled(row.title, value: $0) }"),
])
func frontendRejectsInvalidItemToggleBinding(_ getter: String, _ setter: String) throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SettingsModel: RefractModel {
        var rows: [SettingRow] { get }
        func setEnabled(_ id: Int, value: Bool)
    }
    struct SettingRow: Identifiable { let id: Int; let title: String; let enabled: Bool }
    struct ItemToggle: View {
        let model: SettingsModel
        var body: some View {
            List(model.rows) { row in
                Toggle("settings.item\\(row.id)", isOn: Binding(\(getter), set: \(setter)))
            }
        }
    }
    """))
    #expect(unit.diagnostics.contains { $0.code == "state.invalid_projection" })
    #expect(unit.module.screens.isEmpty)
}

@Test func frontendRejectsUnknownToggleProjection() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct ToggleRow: View {
        @State private var isEnabled: Bool = false
        var body: some View { Toggle("settings.enabled", isOn: $other) }
    }
    """))
    #expect(unit.diagnostics.contains { $0.code == "state.invalid_projection" })
    #expect(unit.module.screens.isEmpty)
}

@Test(arguments: [
    ("@State private var displayName: String = \"\"", ValueProperty.state("displayName")),
    ("@Binding var displayName: String", ValueProperty.binding("displayName")),
])
func frontendParsesLocalizedTextFieldProjection(_ declaration: String, _ expected: ValueProperty) throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct NameRow: View {
        \(declaration)
        var body: some View { TextField("settings.display.name", text: $displayName) }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .textInput(placeholder, value, _, _) = unit.module.screens.first?.body else {
        Issue.record("Expected a typed text input")
        return
    }
    #expect(placeholder?.value == .localizedText(LocalizedText(key: "settings.display.name")))
    #expect(value.value == .valueProperty(expected))
}

@Test func frontendRejectsNonStringTextFieldProjection() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct NameRow: View {
        @State private var count: Int = 0
        var body: some View { TextField("settings.display.name", text: $count) }
    }
    """))
    #expect(unit.diagnostics.contains { $0.code == "state.invalid_projection" })
    #expect(unit.module.screens.isEmpty)
}

@Test func frontendRejectsNonCanonicalTextFieldTitle() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct NameRow: View {
        @State private var displayName: String = ""
        var body: some View { TextField("Display name", text: $displayName) }
    }
    """))
    #expect(unit.diagnostics.contains { $0.code == "state.invalid_projection" })
    #expect(unit.module.screens.isEmpty)
}
