import Foundation
import Testing
import RefractGolden

@Suite("Generation reliability")
struct GenerationReliabilityTests {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func readyCorpusIsStableAcrossRepeatedGeneration() throws {
        let cases = try CorpusLoader.load(repository: Self.repository).filter { $0.status == .ready }
        for fixture in cases {
            let reference = try GoldenRunner.generate(fixture)
            #expect(GoldenRunner.differences(for: fixture, result: reference) == [],
                    "Hand-reviewed corpus differs for \(fixture.name)")
            for _ in 0..<4 {
                let generated = try GoldenRunner.generate(fixture)
                #expect(generated.kotlin == reference.kotlin, "Kotlin differs at \(fixture.name)")
                #expect(generated.arkTS == reference.arkTS, "ArkTS differs at \(fixture.name)")
                #expect(generated.diagnostics == reference.diagnostics, "Diagnostics differ at \(fixture.name)")
            }
        }
    }

    @Test(arguments: [
        "struct Bad: View { var body: some View { Text(verbatim: \"unterminated\" } ",
        "struct Bad: View { var body: some View { UnknownView() } }",
        "struct Bad: View { var body: some View { Text(verbatim: \"one\") } }\nstruct Bad: View { var body: some View { Text(verbatim: \"two\") } }",
    ])
    func everyFailureReturnsNoPartialNativeSource(source: String) throws {
        let fixture = FixtureCase(name: "malformed", status: .ready, input: source, mapping: nil,
                                  expectedKotlin: "not used", expectedArkTS: "not used", expectedDiagnostics: "not used")
        let reference = try GoldenRunner.generate(fixture)
        #expect(reference.kotlin == nil)
        #expect(reference.arkTS == nil)
        #expect(!reference.diagnostics.isEmpty)
        #expect(reference.diagnostics.allSatisfy {
            $0.location?.file == "Input.swift" && ($0.location?.line ?? 0) > 0
                && ($0.location?.column ?? 0) > 0
        })
        for _ in 0..<8 {
            let generated = try GoldenRunner.generate(fixture)
            #expect(generated.kotlin == nil && generated.arkTS == nil)
            #expect(generated.diagnostics == reference.diagnostics)
        }
    }

    @Test(arguments: [
        "{",
        "{\"schemaVersion\":1,\"schemaVersion\":1}",
        "{\"schemaVersion\":1,\"unknown\":true}",
        "{\"schemaVersion\":2}",
        "{\"schemaVersion\":1,\"android\":{},\"harmonyOS\":{}}",
    ])
    func malformedMappingsReturnNoPartialNativeSource(mapping: String) throws {
        let fixture = FixtureCase(name: "bad-mapping", status: .ready,
                                  input: "struct Hello: View { var body: some View { Text(verbatim: \"Hello\") } }",
                                  mapping: mapping, expectedKotlin: "not used", expectedArkTS: "not used",
                                  expectedDiagnostics: "not used")
        let reference = try GoldenRunner.generate(fixture)
        #expect(reference.kotlin == nil && reference.arkTS == nil)
        #expect(!reference.diagnostics.isEmpty)
        #expect(reference.diagnostics.allSatisfy { $0.location != nil })
        for _ in 0..<8 {
            let generated = try GoldenRunner.generate(fixture)
            #expect(generated.kotlin == nil && generated.arkTS == nil)
            #expect(generated.diagnostics == reference.diagnostics)
        }
    }
}
