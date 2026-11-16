import Testing
import Foundation
@testable import RefractCompose
import RefractFrontend
import RefractIR
import RefractMapping

private func staticIdentityMapping() throws -> Mapping {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("refract-static-identity-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let keys = ["settings.profile", "settings.display.name", "settings.preferences", "settings.notifications", "settings.save"]
    let android = keys.map { "    <string name=\"\($0.replacingOccurrences(of: ".", with: "_"))\">Value</string>" }.joined(separator: "\n")
    try "<resources>\n\(android)\n</resources>".write(to: directory.appendingPathComponent("strings.xml"), atomically: true, encoding: .utf8)
    let harmony = keys.map { "    {\"name\":\"\($0.replacingOccurrences(of: ".", with: "_"))\",\"value\":\"Value\"}" }.joined(separator: ",\n")
    try "{\"string\":[\n\(harmony)\n]}".write(to: directory.appendingPathComponent("string.json"), atomically: true, encoding: .utf8)
    let registry = Dictionary(uniqueKeysWithValues: keys.map { ($0, $0.replacingOccurrences(of: ".", with: "_")) })
    return Mapping(
        android: PlatformMapping(resources: Resources(className: "refract.generated.R", catalog: "strings.xml", strings: registry)),
        harmonyOS: PlatformMapping(resources: Resources(catalog: "string.json", strings: registry)),
        resourceBaseURL: directory)
}

@Test func staticControlRowsUseSourceDerivedIdentities() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SettingsModel: RefractModel {
        var title: String { get }
        func save()
    }
    struct SettingsScreen: View {
        let model: SettingsModel
        @Binding var notificationsEnabled: Bool
        @State private var displayName: String = ""
        var body: some View {
            List {
                Section("settings.profile") {
                    Text(model.title)
                    TextField("settings.display.name", text: $displayName)
                }
                Section("settings.preferences") {
                    Toggle("settings.notifications", isOn: $notificationsEnabled)
                }
                Section {
                    Button("settings.save") { model.save() }
                }
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let output = try ComposeBackend().generate(module: unit.module, mapping: staticIdentityMapping())
    #expect(output.contains("key = \"row:title\""))
    #expect(output.contains("key = \"row:display-name\""))
    #expect(output.contains("key = \"row:notifications\""))
    #expect(output.contains("key = \"row:save\""))
    #expect(!output.contains("key = \"row:displayName\""))
    #expect(!output.contains("key = \"row:notificationsEnabled\""))
}

@Test func unsupportedStaticActionHasAnIdentityDiagnostic() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Settings", body: .list(children: [
            .section(header: nil, children: [
                .button(label: .text(Expression(.stringLiteral("Save")), modifiers: [], location: nil),
                        action: .increment(.state("count"), Expression(.numberLiteral("1"))),
                        modifiers: [], location: nil),
            ], location: nil),
        ], modifiers: [], location: nil)),
    ])
    #expect(throws: Diagnostic.self) {
        _ = try ComposeBackend().generate(module: module)
    }
}
