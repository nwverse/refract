import Testing
import Foundation
@testable import RefractArkUI
import RefractIR
import RefractMapping

private func secureMapping() throws -> Mapping {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("refract-ark-secure-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try """
    <resources><string name="settings_password">Password</string></resources>
    """.write(to: directory.appendingPathComponent("strings.xml"), atomically: true, encoding: .utf8)
    try """
    {"string":[{"name":"settings_password","value":"Password"}]}
    """.write(to: directory.appendingPathComponent("string.json"), atomically: true, encoding: .utf8)
    return Mapping(
        android: PlatformMapping(resources: Resources(className: "R", catalog: "strings.xml",
                                                      strings: ["settings.password": "settings_password"])),
        harmonyOS: PlatformMapping(resources: Resources(namespace: "app", stringTable: "string", catalog: "string.json",
                                                        strings: ["settings.password": "settings_password"])),
        resourceBaseURL: directory)
}

@Test func arkUISecureInputIsObscuredByDefault() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "PasswordRow",
               states: [.state(name: "password", type: .string, initialValue: Expression(.stringLiteral("")), location: nil)],
               body: .secureInput(
                placeholder: Expression(.localizedText(LocalizedText(key: "settings.password"))),
                value: Expression(.valueProperty(.state("password"))),
                reveal: nil, modifiers: [], location: nil)),
    ])
    let output = try ArkUIBackend().generate(module: module, mapping: secureMapping())
    #expect(output.contains(".type(InputType.Password)"))
    #expect(output.contains("TextInput({ placeholder: $r('app.string.settings_password'), text: this.password })"))
    #expect(output.contains(".onChange((value: string) => {"))
    #expect(!output.contains("InputType.Normal"))
}

@Test func arkUISecureInputRevealTogglesInputType() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "PasswordRow",
               states: [
                .state(name: "password", type: .string, initialValue: Expression(.stringLiteral("")), location: nil),
                .state(name: "isRevealed", type: .bool, initialValue: Expression(.boolLiteral(false)), location: nil),
               ],
               body: .secureInput(
                placeholder: Expression(.localizedText(LocalizedText(key: "settings.password"))),
                value: Expression(.valueProperty(.state("password"))),
                reveal: Expression(.valueProperty(.state("isRevealed")), type: .bool, location: nil),
                modifiers: [], location: nil)),
    ])
    let output = try ArkUIBackend().generate(module: module, mapping: secureMapping())
    #expect(output.contains(".type(this.isRevealed ? InputType.Normal : InputType.Password)"))
}

@Test func arkUISecureInputNeverDisclosesSecret() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "PasswordRow",
               states: [.state(name: "password", type: .string, initialValue: Expression(.stringLiteral("")), location: nil)],
               body: .secureInput(
                placeholder: Expression(.localizedText(LocalizedText(key: "settings.password"))),
                value: Expression(.valueProperty(.state("password"))),
                reveal: nil, modifiers: [], location: nil)),
    ])
    let output = try ArkUIBackend().generate(module: module, mapping: secureMapping())
    let forbiddenFragments = [
        "console.", "hilog", "HiLog", "Logger.",
        "Text(this.password)", "Text(`${this.password}`)",
    ]
    for fragment in forbiddenFragments {
        #expect(!output.contains(fragment), Comment(rawValue: "Generated ArkTS leaked: \(fragment)"))
    }
}
