import Foundation
import Testing
import RefractIR
@testable import RefractMapping

@Test func typedLayoutMappingKeepsHarmonyResourceConfiguration() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/compose-typed-layout/refract.json")
    let mapping = try Mapping.load(contentsOf: url)
    #expect(mapping.harmonyOS.resources.namespace == "app")
    #expect(mapping.harmonyOS.resources.stringTable == "string")
    #expect(mapping.harmonyOS.resources.catalog == "resources/base/element/string.json")
    #expect(mapping.resourceBaseURL != nil)
    let resource = try mapping.stringResource("settings.general", platform: .harmonyOS)
    #expect(resource.nativeName == "settings_general")
}

@Test func canonicalNamesAreSharedAndCannotAlias() throws {
    #expect(try StringResourceName.make(key: "settings.title") == "settings_title")
    #expect(try StringResourceName.make(key: "profile.message2") == "profile_message2")
    for key in ["settings_title", "Settings.title", "settings.title-name", "settings..title", "", "1settings.title"] {
        #expect(throws: Diagnostic.self) { try StringResourceName.make(key: key) }
    }
}

@Test func formatsUsePortablePositionalScalarArguments() throws {
    #expect(try StringFormat.parse("Hello %1$s, %2$d / %3$f, 100%%").arguments == [.string, .int, .double])
    #expect(try StringFormat.parse("No arguments").arguments.isEmpty)
    #expect(try StringFormat.parse("%2$s %1$s").arguments == [.string, .string])
    for format in ["Hello %s", "%1$05d", "%1$@", "%1$s %1$s", "%", "%999999999999999999999$s"] {
        #expect(throws: Diagnostic.self) { try StringFormat.parse(format) }
    }
}

@Test func nativeCatalogsDecodeTextAndValidateFormats() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try write("""
    <resources>
      <string name="settings_title">Settings &amp; privacy</string>
      <string name="profile_greeting">Hello %1$s, you have %2$d items (%3$f)</string>
    </resources>
    """, named: "strings.xml", in: directory)
    try write("""
    {"string": [
      {"name": "settings_title", "value": "Settings & privacy"},
      {"name": "profile_greeting", "value": "Hello %1$s, you have %2$d items (%3$f)"}
    ]}
    """, named: "string.json", in: directory)
    let catalog = try StringResourceLoader.load(android: "strings.xml", harmony: "string.json", base: directory)
    #expect(catalog["settings_title"]?.value == "Settings & privacy")
    #expect(catalog["profile_greeting"]?.format.arguments == [.string, .int, .double])
}

@Test func mismatchedCatalogFormatsAreRejected() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try write(#"<resources><string name="profile_greeting">%1$s</string></resources>"#,
              named: "strings.xml", in: directory)
    try write(#"{"string": [{"name": "profile_greeting", "value": "%1$d"}]}"#,
              named: "string.json", in: directory)
    #expect(throws: Diagnostic.self) {
        try StringResourceLoader.load(android: "strings.xml", harmony: "string.json", base: directory)
    }
}

@Test(arguments: [
    #"<resources><string name="duplicate">one</string><string name="duplicate">two</string></resources>"#,
    #"<resources><string name="markup"><b>not plain text</b></string></resources>"#,
    #"<resources><string name="external"><xliff:g>not portable</xliff:g></string></resources>"#,
    #"<resources><string name="bad" translatable="false">not localized</string></resources>"#,
])
func invalidAndroidCatalogsAreRejected(contents: String) throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try write(contents, named: "strings.xml", in: directory)
    #expect(throws: Diagnostic.self) { try StringResourceLoader.loadAndroid(directory.appendingPathComponent("strings.xml")) }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("refract-localization-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ contents: String, named name: String, in directory: URL) throws {
    try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
}
