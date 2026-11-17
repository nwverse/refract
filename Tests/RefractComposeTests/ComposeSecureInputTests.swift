import Testing
import Foundation
@testable import RefractCompose
import RefractIR
import RefractMapping

private func secureMapping() throws -> Mapping {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("refract-secure-\(UUID().uuidString)", isDirectory: true)
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
        harmonyOS: PlatformMapping(resources: Resources(catalog: "string.json",
                                                        strings: ["settings.password": "settings_password"])),
        resourceBaseURL: directory)
}

@Test func composeSecureInputIsObscuredByDefault() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "PasswordRow",
               states: [.state(name: "password", type: .string, initialValue: Expression(.stringLiteral("")), location: nil)],
               body: .secureInput(
                placeholder: Expression(.localizedText(LocalizedText(key: "settings.password"))),
                value: Expression(.valueProperty(.state("password"))),
                reveal: nil, modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module, mapping: secureMapping())
    #expect(output.contains("import androidx.compose.material3.TextField"))
    #expect(output.contains("import androidx.compose.ui.text.input.PasswordVisualTransformation"))
    #expect(output.contains("import androidx.compose.ui.text.input.KeyboardType"))
    #expect(output.contains("import androidx.compose.foundation.text.KeyboardOptions"))
    #expect(output.contains("visualTransformation = PasswordVisualTransformation(),"))
    #expect(output.contains("keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),"))
    // The reveal branch must not appear when no `.secureReveal` modifier was given.
    #expect(!output.contains("VisualTransformation.None"))
}

@Test func composeSecureInputRevealTogglesVisualTransformation() throws {
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
    let output = try ComposeBackend().generate(module: module, mapping: secureMapping())
    #expect(output.contains("visualTransformation = if (isRevealed) VisualTransformation.None else PasswordVisualTransformation(),"))
}

@Test func composeSecureInputNeverDisclosesSecret() throws {
    // Negative disclosure: no secret literal, no logging, no echo of the bound value outside the control.
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "PasswordRow",
               states: [.state(name: "password", type: .string, initialValue: Expression(.stringLiteral("")), location: nil)],
               body: .secureInput(
                placeholder: Expression(.localizedText(LocalizedText(key: "settings.password"))),
                value: Expression(.valueProperty(.state("password"))),
                reveal: nil, modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module, mapping: secureMapping())
    let forbiddenFragments = [
        "println(", "print(", "Log.", "android.util.Log",
        "Text(text = password)", "Text(password)",
        "stringResource(R.string.settings_password) + password",
    ]
    for fragment in forbiddenFragments {
        #expect(!output.contains(fragment), Comment(rawValue: "Generated Kotlin leaked: \(fragment)"))
    }
}

@Test func composeSecureInputRejectsNonProjectedValue() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "PasswordRow", body: .secureInput(
            placeholder: Expression(.localizedText(LocalizedText(key: "settings.password"))),
            value: Expression(.reference("password")),
            reveal: nil, modifiers: [], location: nil)),
    ])
    #expect(throws: Diagnostic.self) {
        _ = try ComposeBackend().generate(module: module, mapping: secureMapping())
    }
}
