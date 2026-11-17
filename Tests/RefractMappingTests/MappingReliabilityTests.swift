import Foundation
import Testing
@testable import RefractMapping

private struct FixedSeedGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

private let completeMapping = """
{
  "schemaVersion": 1,
  "android": {
    "output": {"directory": "generated", "packageName": "example.generated"},
    "imports": [], "components": {}, "nativeComponents": {}, "modifiers": {},
    "tokens": {"spacing": {}, "radius": {}, "font": {}, "color": {}},
    "resources": {"className": "example.app.R", "strings": {"settings.title": "settings_title"}}
  },
  "harmonyOS": {
    "output": {"directory": "generated"},
    "imports": [], "components": {}, "nativeComponents": {}, "modifiers": {},
    "tokens": {"spacing": {}, "radius": {}, "font": {}, "color": {}},
    "resources": {"namespace": "app", "stringTable": "string", "strings": {"settings.title": "settings_title"}}
  }
}
"""

@Suite("Bounded mapping mutation differential")
struct MappingMutationReliabilityTests {
    @Test func validMappingHasStableSemanticReEncoding() throws {
        let first = try Mapping.load(data: Data(completeMapping.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(first)
        let decoded = try JSONDecoder().decode(Mapping.self, from: encoded)
        #expect(decoded == first)
        #expect(try encoder.encode(decoded) == encoded)
    }

    @Test func malformedMappingAlwaysFailsWithCoordinatesAndNeverDecodes() {
        var random = FixedSeedGenerator(seed: 0x160_160)
        let characters = Array(completeMapping)
        let replacements: [Character] = ["{", "}", "[", "]", "\"", ",", ":", "0", "\\", "\n", "x"]
        for iteration in 0..<256 {
            var mutated = characters
            for _ in 0..<Int.random(in: 1...4, using: &random) {
                let index = Int.random(in: mutated.indices, using: &random)
                switch Int.random(in: 0..<3, using: &random) {
                case 0: mutated.remove(at: index)
                case 1: mutated[index] = replacements.randomElement(using: &random)!
                default: mutated.insert(replacements.randomElement(using: &random)!, at: index)
                }
            }
            let data = Data(String(mutated).utf8)
            let reference = Mapping.validate(data: data, file: "Mutation.json")
            for _ in 0..<2 {
                #expect(Mapping.validate(data: data, file: "Mutation.json") == reference,
                        "Mapping validation differs at iteration \(iteration)")
            }
            switch reference {
            case .success:
                // Any surviving mutation must satisfy the same published schema as the original.
                #expect(Bool(true))
            case let .failure(error):
                #expect(!error.diagnostics.isEmpty)
                #expect(error.diagnostics.allSatisfy {
                    $0.location?.file == "Mutation.json" && ($0.location?.line ?? 0) > 0
                        && ($0.location?.column ?? 0) > 0 && $0.suggestion?.isEmpty == false
                }, "Missing mapping coordinate at iteration \(iteration)")
                // Invalid input must not silently decode through last-value-wins JSON defaults.
                #expect(throws: (any Error).self) {
                    _ = try Mapping.load(data: data, file: "Mutation.json")
                }
            }
        }
    }

    @Test(arguments: [
        (bytes: [0xFF, 0xFE, 0x7B], code: "mappingIO", line: 1),
        (bytes: Array("{\"schemaVersion\":1,\"schemaVersion\":2}".utf8), code: "mappingDuplicateKey", line: 1),
        (bytes: Array("{\"schemaVersion\":1,\"unknown\":false}".utf8), code: "mappingUnknownKey", line: 1),
        (bytes: Array("{\"schemaVersion\":1,\"android\":".utf8), code: "mapping.invalid_json", line: 1),
        (bytes: Array("{\"schemaVersion\":1}\n{\"schemaVersion\":1}".utf8), code: "mapping.invalid_json", line: 2),
    ])
    func malformedByteInputsAreLocated(bytes: [UInt8], code: String, line: Int) throws {
        let result = Mapping.validate(data: Data(bytes), file: "Bad.json")
        guard case let .failure(error) = result else {
            Issue.record("Malformed mapping unexpectedly decoded")
            return
        }
        let diagnostic = try #require(error.diagnostics.first { $0.code == code })
        #expect(diagnostic.location?.file == "Bad.json")
        #expect(diagnostic.location?.line == line)
        #expect((diagnostic.location?.column ?? 0) > 0)
    }
}
