import Testing
import Foundation
@testable import RefractCompose
import RefractIR
import RefractMapping

private func textFieldMapping() throws -> Mapping {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("refract-textfield-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try """
    <resources><string name="settings_display_name">Display name</string></resources>
    """.write(to: directory.appendingPathComponent("strings.xml"), atomically: true, encoding: .utf8)
    try """
    {"string":[{"name":"settings_display_name","value":"Display name"}]}
    """.write(to: directory.appendingPathComponent("string.json"), atomically: true, encoding: .utf8)
    return Mapping(
        android: PlatformMapping(resources: Resources(className: "R", catalog: "strings.xml",
                                                      strings: ["settings.display.name": "settings_display_name"])),
        harmonyOS: PlatformMapping(resources: Resources(catalog: "string.json",
                                                        strings: ["settings.display.name": "settings_display_name"])),
        resourceBaseURL: directory)
}

@Test func composeEmitsLocalizedTextFieldWithStateUpdate() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "NameRow",
               states: [.state(name: "displayName", type: .string, initialValue: Expression(.stringLiteral("")), location: nil)],
               body: .textInput(
                placeholder: Expression(.localizedText(LocalizedText(key: "settings.display.name"))),
                value: Expression(.valueProperty(.state("displayName"))),
                modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module, mapping: textFieldMapping())
    #expect(output.contains("import androidx.compose.material3.TextField"))
    #expect(output.contains("value = displayName"))
    #expect(output.contains("onValueChange = { value -> displayName = value }"))
    #expect(output.contains("label = { Text(text = stringResource(R.string.settings_display_name)) }"))
    #expect(!output.contains("import refract."))
}

@Test func composeTextFieldUsesBindingCallback() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "NameRow",
               states: [.binding(name: "displayName", type: .string, location: nil)],
               body: .textInput(
                placeholder: Expression(.localizedText(LocalizedText(key: "settings.display.name"))),
                value: Expression(.valueProperty(.binding("displayName"))),
                modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module, mapping: textFieldMapping())
    #expect(output.contains("onValueChange = onDisplayNameChange"))
}

@Test func composeRejectsTextFieldWithoutWritableValue() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "NameRow", body: .textInput(
            placeholder: Expression(.localizedText(LocalizedText(key: "settings.display.name"))),
            value: Expression(.reference("displayName")), modifiers: [], location: nil)),
    ])
    #expect(throws: Diagnostic.self) {
        _ = try ComposeBackend().generate(module: module)
    }
}
