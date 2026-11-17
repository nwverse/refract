import Foundation
import Testing
import RefractGolden

struct GoldenTests {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test(arguments: try CorpusLoader.load(repository: repository))
    func golden(_ fixture: FixtureCase) throws {
        if fixture.status == .pending {
            withKnownIssue("Pending conformance case: \(fixture.name). Its owner must mark it ready when implemented.") {
                Issue.record("Pending cases do not claim successful generation.")
            }
            return
        }
        let result = try GoldenRunner.generate(fixture)
        #expect(GoldenRunner.differences(for: fixture, result: result) == [])
    }
}

struct CorpusTests {
    @Test func malformedMappingUsesTheGoldenDiagnosticContract() throws {
        let fixture = FixtureCase(name: "bad-mapping", status: .ready,
                                  input: "struct Bad: View { var body: some View { Gauge(\"photo\") } }",
                                  mapping: "not JSON", expectedKotlin: nil, expectedArkTS: nil,
                                  expectedDiagnostics: "ignored")
        let result = try GoldenRunner.generate(fixture)
        #expect(result.kotlin == nil && result.arkTS == nil)
        #expect(result.diagnostics.map(\.code) == ["RFNATIVE001", "mapping.invalid_json"])
        #expect(result.diagnostics.allSatisfy { $0.location != nil })
    }

    @Test func repositoryManifestIsExplicitAndDeterministic() throws {
        let root = GoldenTests.repository
        let cases = try CorpusLoader.load(repository: root)
        #expect(cases.map(\.name) == cases.map(\.name).sorted())
        for required in ["hello", "pending-contract", "rejected-image", "localization/plain",
                         "localization/formatted", "localization/missing-android", "localization/missing-harmony"] {
            #expect(cases.map(\.name).contains(required))
        }
        #expect(cases.map(\.name).count == Set(cases.map(\.name)).count)
        #expect(cases.contains { $0.status == .ready })
        #expect(cases.contains { $0.name == "hello" && $0.status == .ready })
        #expect(cases.contains { $0.name == "rejected-image" && $0.status == .ready })
        #expect(cases.filter { $0.name.hasPrefix("localization/") }.allSatisfy { $0.status == .ready })
        #expect(cases.filter { $0.name.hasPrefix("interop-") && $0.status == .ready }.map(\.name) == [
            "interop-document-preview", "interop-document-preview-reject",
            "interop-native-animation", "interop-native-callers", "interop-native-component", "interop-native-measurement", "interop-native-mismatch",
            "interop-native-missing", "interop-native-undeclared", "interop-platform-text-localized-rejected",
            "interop-platform-value", "interop-platform-value-incomplete", "interop-platform-view",
            "interop-reject-conditional-compilation", "interop-remote-image", "interop-remote-image-reject",
            "interop-text-input-host",
        ])
        #expect(cases.allSatisfy { !$0.name.hasPrefix("interop-") || $0.status == .ready })
        #expect(try CorpusLoader.load(repository: root).map(\.name) == cases.map(\.name))
    }

    @Test func pendingCasesAreStructuralAndMalformedCasesFail() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fixtures = root.appendingPathComponent("Fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtures.appendingPathComponent("nested/case"),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try write("{ \"schemaVersion\": 1 }", "Corpus.json", in: fixtures)
        #expect(throws: CorpusError.self) { try CorpusLoader.load(repository: root) }
        try write("{ \"schemaVersion\": 1, \"cases\": [] }", "Corpus.json", in: fixtures)
        #expect(throws: CorpusError.self) { try CorpusLoader.load(repository: root) }
        try write(validManifest(path: "../case"), "Corpus.json", in: fixtures)
        #expect(throws: CorpusError.self) { try CorpusLoader.load(repository: root) }
        try write(validManifest(path: "unlisted"), "Corpus.json", in: fixtures)
        #expect(throws: CorpusError.self) { try CorpusLoader.load(repository: root) }
        try write(validManifest(path: "nested/case", status: "pending"), "Corpus.json", in: fixtures)
        #expect(throws: CorpusError.self) { try CorpusLoader.load(repository: root) }

        try write("struct Example: View {}", "Input.swift", in: fixtures.appendingPathComponent("nested/case"))
        try write("Input.swift:1:1: error [unsupportedViewBody]: Unsupported. Suggestion: Use Text.",
                  "Expected.diagnostics", in: fixtures.appendingPathComponent("nested/case"))
        let cases = try CorpusLoader.load(repository: root)
        #expect(cases.count == 1)
        #expect(cases[0].name == "nested/case")
        #expect(cases[0].status == .pending)
        try write(validManifest(path: "nested/case"), "Corpus.json", in: fixtures)
        #expect(try CorpusLoader.load(repository: root)[0].status == .ready)
    }

    @Test func duplicateCasesAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fixtures = root.appendingPathComponent("Fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try write("{ \"schemaVersion\": 1, \"cases\": [{\"path\":\"case\",\"implementationStatus\":\"pending\"},{\"path\":\"case\",\"implementationStatus\":\"ready\"}] }",
                  "Corpus.json", in: fixtures)
        #expect(throws: CorpusError.self) { try CorpusLoader.load(repository: root) }
    }
}

private func validManifest(path: String, status: String = "ready") -> String {
    "{ \"schemaVersion\": 1, \"cases\": [{\"path\": \"\(path)\", \"implementationStatus\": \"\(status)\"}] }"
}

private func write(_ value: String, _ name: String, in directory: URL) throws {
    try Data((value + "\n").utf8).write(to: directory.appendingPathComponent(name))
}
