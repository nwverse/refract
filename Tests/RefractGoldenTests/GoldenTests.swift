import Foundation
import Testing
import RefractFrontend
import RefractIR
import RefractMapping
import RefractCompose
import RefractArkUI

struct GoldenTests {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test(arguments: try FixtureCase.loadAll(in: repository))
    func golden(_ fixture: FixtureCase) throws {
        let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: fixture.input))
        let expected = fixture.expectedDiagnostics ?? ""
        #expect(unit.diagnostics.map { $0.rendered + "\n" }.joined() == expected)
        guard !unit.hasErrors else {
            #expect(fixture.expectedKotlin == nil && fixture.expectedArkTS == nil)
            return
        }
        let mapping: Mapping
        if let contents = fixture.mapping {
            mapping = try JSONDecoder().decode(Mapping.self, from: Data(contents.utf8))
        } else { mapping = .empty }
        #expect(try ComposeBackend().generate(module: unit.module, mapping: mapping) == fixture.expectedKotlin)
        #expect(try ArkUIBackend().generate(module: unit.module, mapping: mapping) == fixture.expectedArkTS)
    }
}

struct FixtureCase: CustomTestStringConvertible, Sendable {
    let name: String
    let input: String
    let mapping: String?
    let expectedKotlin: String?
    let expectedArkTS: String?
    let expectedDiagnostics: String?

    var testDescription: String { name }

    static func loadAll(in root: URL) throws -> [FixtureCase] {
        let folder = root.appendingPathComponent("Fixtures", isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter {
            !$0.hasPrefix(".") && !$0.hasSuffix(".md")
        }.sorted()
        return try names.map { name in
            let directory = folder.appendingPathComponent(name, isDirectory: true)
            return try FixtureCase(name: name,
                input: read(directory, "Input.swift", required: true)!,
                mapping: read(directory, "refract.json", required: false),
                expectedKotlin: read(directory, "Expected.kt", required: false),
                expectedArkTS: read(directory, "Expected.ets", required: false),
                expectedDiagnostics: read(directory, "Expected.diagnostics", required: false))
        }
    }

    private static func read(_ directory: URL, _ file: String, required: Bool) throws -> String? {
        let url = directory.appendingPathComponent(file)
        if !required, !FileManager.default.fileExists(atPath: url.path) { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
