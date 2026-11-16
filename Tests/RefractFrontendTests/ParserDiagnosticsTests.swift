import Testing
@testable import RefractFrontend
import RefractIR

@Test func frontendRejectsMalformedSwiftBeforeBuildingIR() {
    let unit = Frontend.parse(SourceFile(path: "Syntax.swift", contents: """
    import SwiftUI

    struct SyntaxScreen: View {
        var body: some View {
            Text(verbatim: "unterminated"
        }
    }
    """))
    #expect(unit.hasErrors)
    #expect(unit.module.screens.isEmpty)
    #expect(unit.module.nativeDeclarations.isEmpty)
    #expect(unit.module.models.isEmpty)
    #expect(!unit.diagnostics.isEmpty)
    for diagnostic in unit.diagnostics {
        #expect(diagnostic.code == "RFSYN001")
        #expect(diagnostic.location?.file == "Syntax.swift")
        #expect(diagnostic.location?.line != nil)
        #expect(diagnostic.location?.column != nil)
        #expect(diagnostic.suggestion?.contains("Correct the Swift syntax") == true)
    }
    #expect(unit.diagnostics.map(\.code) == Array(repeating: "RFSYN001", count: unit.diagnostics.count))
}

@Test func frontendValidSwiftHasNoParserDiagnostic() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Hello: View { var body: some View { Text(verbatim: "Hello") } }
    """))
    #expect(!unit.diagnostics.contains { $0.code == "RFSYN001" })
    #expect(!unit.module.screens.isEmpty)
}
