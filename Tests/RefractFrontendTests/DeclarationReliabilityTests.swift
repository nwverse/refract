import Testing
@testable import RefractFrontend
import RefractIR

@Suite("Deterministic malformed Swift recovery")
struct MalformedSwiftReliabilityTests {
    @Test(arguments: [
        (source: "struct Broken: View { var body: some View { Text(verbatim: \"unterminated\" }", expectedLine: 1),
        (source: "struct Broken: View { var body: some View { VStack { Text(verbatim: \"one\")", expectedLine: 1),
    ])
    func recoveredTreesNeverProducePartialIR(source: String, expectedLine: Int) {
        let reference = Frontend.parse(SourceFile(path: "Broken.swift", contents: source))
        #expect(reference.hasErrors)
        #expect(reference.module == Module(sourceFile: "Broken.swift", screens: []))
        #expect(reference.diagnostics.allSatisfy {
            $0.code == "RFSYN001" && $0.location?.file == "Broken.swift"
                && $0.location?.line != nil && ($0.location?.line ?? 0) > 0
                && ($0.location?.column ?? 0) > 0 && $0.suggestion?.isEmpty == false
        })
        for _ in 0..<8 {
            #expect(Frontend.parse(SourceFile(path: "Broken.swift", contents: source)) == reference)
        }
    }
}

@Suite("Same-file declaration reliability")
struct DeclarationReliabilityTests {
    @Test(arguments: [
        (name: "Screen", declaration: "struct Screen: View { var body: some View { Text(verbatim: \"placeholder\") } }", line: 2, column: 8),
        (name: "SettingsModel", declaration: "protocol SettingsModel: RefractModel { var title: String { get } }", line: 2, column: 10),
        (name: "Item", declaration: "struct Item: Identifiable { let id: String }", line: 2, column: 8),
        (name: "Content", declaration: "enum Content { case value }", line: 2, column: 6),
    ])
    func duplicateGeneratedDeclarationsAreRejected(name: String, declaration: String, line: Int, column: Int) throws {
        let source = "import SwiftUI\n\n\(declaration)\n\(declaration)\n"
        let unit = Frontend.parse(SourceFile(path: "Duplicate.swift", contents: source))
        #expect(unit.hasErrors)
        #expect(unit.diagnostics.count == 1)
        let diagnostic = try #require(unit.diagnostics.first)
        #expect(diagnostic.code == "RFSYN004")
        #expect(diagnostic.message.contains(name))
        #expect(diagnostic.message.contains("more than once"))
        #expect(diagnostic.suggestion?.contains("unique") == true)
        #expect(diagnostic.location == SourceLocation(file: "Duplicate.swift", line: line + 2, column: column))
        #expect(unit.module.screens.isEmpty)
        #expect(unit.module.models.isEmpty)
        #expect(unit.module.itemTypes.isEmpty)
        #expect(unit.module.enums.isEmpty)
    }

    @Test(arguments: [
        "let helper = 1",
        "protocol Helper { var title: String { get } }",
        "struct Helper {}",
        "enum Helper { case value }",
    ])
    func unrelatedDeclarationsKeepTheirExistingScope(source: String) {
        let unit = Frontend.parse(SourceFile(path: "Helper.swift", contents: source))
        #expect(!unit.hasErrors)
        #expect(unit.module.screens.isEmpty)
    }
}
