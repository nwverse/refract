import RefractArkUI
import RefractCompose
import RefractFrontend
import RefractIR
import Testing

private let enumSource = """
enum Tab {
    case home
    case settings
}

struct TabContent: View {
    let tab: Tab

    var body: some View {
        switch tab {
        case .home:
            Text(verbatim: "Home")
        case .settings:
            Text(verbatim: "Settings")
        }
    }
}
"""

@Test func exhaustiveEnumSwitchProducesTypedNativeBranches() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: enumSource))
    #expect(unit.diagnostics.isEmpty)
    #expect(unit.module.enums.first?.cases == ["home", "settings"])
    #expect(unit.module.screens.first?.parameters.first?.enumName == "Tab")
    let kotlin = try ComposeBackend().generate(module: unit.module)
    #expect(kotlin.contains("public enum class Tab {"))
    #expect(kotlin.contains("when (tab) {"))
    #expect(kotlin.contains("Tab.home -> {"))
    #expect(kotlin.contains("Tab.settings -> {"))
    #expect(!kotlin.contains("else ->"))
    let arkTS = try ArkUIBackend().generate(module: unit.module)
    #expect(arkTS.contains("export enum Tab {"))
    #expect(arkTS.contains("if (this.tab === Tab.home) {"))
    #expect(arkTS.contains("} else if (this.tab === Tab.settings) {"))
    #expect(!arkTS.contains("} else {"))
    #expect(kotlin.index(of: "Text(text = \"Home\")")! < kotlin.index(of: "Text(text = \"Settings\")")!)
    #expect(arkTS.index(of: "Text('Home')")! < arkTS.index(of: "Text('Settings')")!)
    #expect(!kotlin.contains("AnyView"))
    #expect(!arkTS.contains("AnyView"))
}

@Test(arguments: [
    ("switch tab { case .home: Text(verbatim: \"Home\") }", "RFCTRL007"),
    ("switch tab { case .home: Text(verbatim: \"Home\"); case .settings: Text(verbatim: \"Settings\"); case .home: Text(verbatim: \"Again\") }", "RFCTRL007"),
    ("switch tab { case .home: Text(verbatim: \"Home\"); default: Text(verbatim: \"Other\") }", "RFCTRL005"),
])
func invalidSwitchCasesAreRejected(_ statement: String, _ code: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum Tab { case home; case settings }
    struct RejectedSwitch: View {
        let tab: Tab
        var body: some View {
            \(statement)
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == [code])
    #expect(unit.module.screens.isEmpty)
}

@Test(arguments: [
    "enum Content { case text(String) }",
    "enum Content: String { case text = \"text\" }",
    "enum Content { case one, two }",
])
func unsupportedEnumDeclarationsAreRejected(_ declaration: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: declaration))
    #expect(unit.diagnostics.map(\.code) == ["RFCTRL006"])
    #expect(unit.module.enums.isEmpty)
}

@Test func manuallyConstructedSwitchCannotBypassExhaustiveness() {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Bad", body: .switchExpression(
            subject: Expression(.reference("tab")), enumName: "Tab",
            cases: [SwitchCase(name: "home", children: [])], location: nil)),
    ], enums: [EnumDeclaration(name: "Tab", cases: ["home", "settings"])])
    #expect(throws: Diagnostic.self) { _ = try ComposeBackend().generate(module: module) }
    #expect(throws: Diagnostic.self) { _ = try ArkUIBackend().generate(module: module) }
}

@Test func enumInputIsNotImplicitlyAString() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum Tab { case home }
    struct WrongText: View {
        let tab: Tab
        var body: some View { Text("Selected: \\(tab)") }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFSEM002"])
    #expect(unit.module.screens.isEmpty)
}

private extension String {
    func index(of substring: String) -> String.Index? { range(of: substring)?.lowerBound }
}
