import Testing
import Foundation
import RefractGolden

@Test func generationRetainsDeclaredModelInputDiagnostics() throws {
    let fixture = FixtureCase(name: "invalid-model", status: .ready, input: """
    protocol SettingsModel: RefractModel {
        func refresh() async
    }
    struct Screen: View {
        let model: SettingsModel
        let title: String
        var body: some View { Text(verbatim: "Unsupported") }
    }
    """, mapping: """
    {
      "schemaVersion": 1,
      "android": {
        "output": {"directory": "generated", "packageName": "example.generated"},
        "imports": [], "components": {}, "nativeComponents": {}, "modifiers": {},
        "tokens": {"spacing": {}, "radius": {}, "font": {}, "color": {}},
        "resources": {"className": "example.app.R", "strings": {}}
      },
      "harmonyOS": {
        "output": {"directory": "generated"},
        "imports": [], "components": {}, "nativeComponents": {}, "modifiers": {},
        "tokens": {"spacing": {}, "radius": {}, "font": {}, "color": {}},
        "resources": {"namespace": "app", "stringTable": "string", "strings": {}}
      }
    }
    """, expectedKotlin: nil, expectedArkTS: nil, expectedDiagnostics: nil)
    let reference = try GoldenRunner.generate(fixture)
    #expect(reference.kotlin == nil && reference.arkTS == nil)
    #expect(reference.diagnostics.map(\.code) == ["model.invalid_action", "state.invalid_declaration"])
    #expect(reference.diagnostics.map { $0.location?.line } == [2, 5])
    for _ in 0..<8 {
        #expect(try GoldenRunner.generate(fixture).diagnostics == reference.diagnostics)
    }
}

@Test func mappingAwareErrorsAreNotDiscarded() throws {
    let fixture = try #require(CorpusLoader.load(repository: GoldenTests.repository).first {
        $0.name == "v0-reject-binding-initializer"
    })
    let result = try GoldenRunner.generate(fixture)
    #expect(result.diagnostics.map(\.code) == ["state.binding_initializer"])
    #expect(GoldenRunner.differences(for: fixture, result: result) == [])
}
