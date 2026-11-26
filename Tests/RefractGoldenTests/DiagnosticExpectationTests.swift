import Foundation
import Testing
import RefractGolden

struct DiagnosticExpectationTests {
    @Test func emptyDiagnosticExpectationIsRejectedInsteadOfSkippingNativeComparison() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("refract-diagnostic-expectation-\(UUID().uuidString)")
        let fixtures = root.appendingPathComponent("Fixtures")
        let directory = fixtures.appendingPathComponent("rejected-case")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("""
        {"schemaVersion":1,"cases":[{"path":"rejected-case","implementationStatus":"ready"}]}
        """.utf8).write(to: fixtures.appendingPathComponent("Corpus.json"))
        try Data("""
        struct Accepted: View { var body: some View { Text(verbatim: "Accepted") } }
        """.utf8).write(to: directory.appendingPathComponent("Input.swift"))
        try Data().write(to: directory.appendingPathComponent("Expected.diagnostics"))

        #expect(throws: CorpusError.self) { try CorpusLoader.load(repository: root) }
    }

    @Test func diagnosticsOnlyCaseCannotReturnNativeOutput() throws {
        let fixture = FixtureCase(
            name: "unexpected-success", status: .ready,
            input: "struct Accepted: View { var body: some View { Text(verbatim: \"Accepted\") } }",
            mapping: nil, expectedKotlin: nil, expectedArkTS: nil,
            expectedDiagnostics: "Input.swift:1:1: error [example]: Rejected. Suggestion: Fix it.\n"
        )
        let result = GoldenResult(kotlin: "Kotlin", arkTS: "ArkTS", diagnostics: [])
        let differences = GoldenRunner.differences(for: fixture, result: result)

        #expect(differences.contains { $0.contains("diagnostics-only case") })
        #expect(differences.contains { $0.contains("Expected.diagnostics differs") })
    }
}
