import Testing
@testable import RefractFrontend
import RefractIR

@Test(arguments: [
    "func unsupportedHelper() {}",
    "init() { self.title = \"unused\" }",
    "struct Nested {}",
    "enum Nested { case value }",
    "var computed: String { \"hidden\" }",
    "var observed: String = \"hidden\" { didSet {} }",
])
func frontendRejectsUnsupportedViewDeclarations(declaration: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct MethodScreen: View {
        \(declaration)

        var body: some View {
            Text(verbatim: "kept")
        }
    }
    """))
    #expect(unit.hasErrors)
    #expect(unit.module.screens.isEmpty)
    #expect(unit.diagnostics.map(\.code) == ["RFSYN004"])
    #expect(unit.diagnostics[0].location?.line == 2)
    #expect(unit.diagnostics[0].suggestion?.contains("model protocol") == true)
}

@Test func frontendRetainsSpecificStateDiagnostics() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct InvalidState: View {
        @ObservedObject var model: LegacyModel
        var body: some View { Text(verbatim: "kept") }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["state.invalid_declaration"])
    #expect(!unit.diagnostics.contains { $0.code == "RFSYN004" })
}

@Test func frontendAllowsDocumentedTypedInputs() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct InputScreen: View {
        let title: String
        var body: some View { Text(title) }
    }
    """))
    #expect(!unit.diagnostics.contains { $0.code == "RFSYN004" })
}
