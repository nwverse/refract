import Foundation
import RefractIR
import Testing
@testable import RefractMapping

@Suite("Mapping loader and validation")
struct MappingTests {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Fixtures")

    @Test(arguments: ["missing-resource"])
    func completeMappingsLoad(name: String) throws {
        let url = Self.fixtures.appendingPathComponent("\(name)/refract.json")
        let mapping = try Mapping.load(contentsOf: url)
        #expect(mapping.schemaVersion == 1)
        let card = try mapping.component(named: "CardRow", platform: .android)
        #expect(card.parameters == [Parameter(label: "title", type: .stringKey)])
        #expect(card.hasContent)
        #expect(try mapping.token("DesignSpacing.medium", category: .spacing, platform: .android)
            == mapping.android.tokens.spacing["DesignSpacing.medium"])
        #expect(mapping.android.output.directory.split(separator: "/").allSatisfy { $0 != "." && $0 != ".." })
    }

    @Test func pairedMappingsResolveDifferentCalls() throws {
        let a = try mapping(target: "CardRow", argument: "title", token: "DesignSpacing.medium", package: "example.generated")
        let b = try mapping(target: "ContentCard", argument: "heading", token: "CompactSpace.medium", package: "sample.ui")
        let aCard = try a.component(named: "CardRow", platform: .android)
        let bCard = try b.component(named: "CardRow", platform: .android)
        #expect(aCard.target == "CardRow")
        #expect(bCard.target == "ContentCard")
        #expect(aCard.arguments.first?.target == "title")
        #expect(bCard.arguments.first?.target == "heading")
        #expect(a.android.output.packageName != b.android.output.packageName)
        #expect(try a.token("DesignSpacing.medium", category: .spacing, platform: .harmonyOS)
            != b.token("DesignSpacing.medium", category: .spacing, platform: .harmonyOS))
    }

    @Test func invalidSchemaFixtureHasExactCoordinatesAndNoLastValueWins() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("invalid-schema/refract.json"))
        let expected = try String(contentsOf: Self.fixtures.appendingPathComponent("invalid-schema/Expected.diagnostics"), encoding: .utf8)
        let actual = try diagnostics(data).map(\.rendered).joined(separator: "\n") + "\n"
        #expect(actual == expected)
    }

    @Test func platformDriftFixtureHasExactCoordinate() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("platform-drift/refract.json"))
        let expected = try String(contentsOf: Self.fixtures.appendingPathComponent("platform-drift/Expected.diagnostics"), encoding: .utf8)
        let actual = try diagnostics(data).map(\.rendered).joined(separator: "\n") + "\n"
        #expect(actual == expected)
    }

    @Test(arguments: [
        (json: "{\"schemaVersion\":1,\"unknown\":true}", code: "mappingUnknownKey", line: 1),
        (json: "{\"schemaVersion\":2}", code: "mappingVersion", line: 1),
        (json: "{\"schemaVersion\":\"1\"}", code: "mappingType", line: 1),
        (json: "{\"schemaVersion\":1,}", code: "mappingSyntax", line: 1),
        (json: "{\"schemaVersion\":1\n", code: "mappingSyntax", line: 2),
        (json: "{\"schemaVersion\":1,\"schemaVersion\":1}", code: "mappingDuplicateKey", line: 1)
    ])
    func malformedAndUnknownInput(test: (json: String, code: String, line: Int)) throws {
        let results = try diagnostics(Data(test.json.utf8))
        #expect(results.contains { $0.code == test.code && $0.location?.line == test.line })
    }

    @Test func validUnicodeEscapesAreDecoded() throws {
        let document = try MappingJSONDocument(data: Data("{\"schemaVersion\":1,\"x\":\"\\uD83D\\uDE00\"}".utf8), file: "refract.json")
        #expect(document.root.property("x")?.string == "😀")
    }

    @Test(arguments: ["\\uD800", "\\uDC00", "\\uD800x", "\\uD800\\u0041", "\\x20"])
    func invalidUnicodeIsRejected(escape: String) throws {
        let data = Data("{\"schemaVersion\":1,\"x\":\"\(escape)\"}".utf8)
        #expect(try diagnostics(data).contains { $0.code == "mappingSyntax" })
    }

    @Test func missingMappingsAreDiagnostics() throws {
        let mapping = Mapping.empty
        #expect(throws: Diagnostic.self) { try mapping.component(named: "Missing", platform: .android) }
        #expect(throws: Diagnostic.self) { try mapping.token("Missing.value", category: .spacing, platform: .android) }
        #expect(throws: Diagnostic.self) { try mapping.stringResource("missing.key", platform: .android) }
        #expect(throws: Diagnostic.self) { try mapping.component(named: "Missing", native: true, platform: .harmonyOS) }
    }

    @Test func resourcesRequireNormalizedNamesAndValidKeys() throws {
        let resources = Resources(className: "example.app.R", strings: ["settings.title": "settings_title"])
        let mapping = Mapping(android: PlatformMapping(resources: resources))
        let resolved = try mapping.stringResource("settings.title", platform: .android)
        #expect(resolved.nativeName == "settings_title")
        #expect(resolved.className == "example.app.R")
        #expect(throws: Diagnostic.self) { try mapping.stringResource("Settings.title", platform: .android) }
    }

    @Test func legacyNativeRegistryIsNormalized() throws {
        let data = Data("""
        {"version":1,"nativeComponents":[{"swift":"RoutePreview","android":{"kind":"composable","symbol":"RoutePreview","module":"example.maps","parameters":[{"swift":"zoom","name":"cameraZoom","type":"Double"},{"swift":"showsTraffic","name":"showsTraffic","type":"Boolean"}]},"harmonyOS":{"kind":"component","symbol":"RoutePreview","module":"example.maps","parameters":[{"swift":"zoom","name":"cameraZoom","type":"number"},{"swift":"showsTraffic","name":"showsTraffic","type":"boolean"}]}}]}
        """.utf8)
        let mapping = try Mapping.load(data: data).get()
        let native = try mapping.component(named: "RoutePreview", native: true, platform: .android)
        #expect(native.target == "RoutePreview")
        #expect(native.module == "example.maps")
        #expect(native.parameters == [Parameter(label: "zoom", type: .double),
                                     Parameter(label: "showsTraffic", type: .bool)])
        #expect(native.arguments.map(\.target) == ["cameraZoom", "showsTraffic"])
        #expect(try mapping.component(named: "RoutePreview", native: true, platform: .harmonyOS).argumentStyle == .object)
    }

    @Test func schemaIsPackaged() throws {
        let schema = try MappingJSONDocument(data: Data(Mapping.schemaJSON.utf8), file: "refract.schema.json")
        #expect(schema.root.property("$schema")?.string == "https://json-schema.org/draft/2020-12/schema")
        #expect(schema.root.property("required")?.array?.map(\.string) == ["schemaVersion", "android", "harmonyOS"])
    }

    private func mapping(target: String, argument: String, token: String, package: String) throws -> Mapping {
        let text = """
        {
          "schemaVersion":1,
          "android": {
            "output":{"directory":"generated","packageName":"\(package)"},"imports":[],
            "components":{"CardRow":{
              "parameters":[{"label":"title","type":"stringKey","required":true}],
              "content":"trailingClosure","modifiers":["padding"],"target":"\(target)","argumentStyle":"named",
              "arguments":[{"source":"title","target":"\(argument)"}],"modifierParameter":"modifier",
              "attributes":{"padding":{"kind":"chain","target":"padding","arguments":[{"source":"_"}]}}
            }},
            "nativeComponents":{},"modifiers":{"padding":{"parameters":[{"label":"_","type":"length","required":true}]}},
            "tokens":{"spacing":{"DesignSpacing.medium":"\(token)"},"radius":{},"font":{},"color":{}},
            "resources":{"className":"example.app.R","strings":{}}
          },
          "harmonyOS": {
            "output":{"directory":"generated"},"imports":[],
            "components":{"CardRow":{
              "parameters":[{"label":"title","type":"stringKey","required":true}],
              "content":"builder","modifiers":["padding"],"target":"\(target)","argumentStyle":"object",
              "arguments":[{"source":"title","target":"\(argument)"}],
              "attributes":{"padding":{"kind":"chain","target":"padding","arguments":[{"source":"_"}]}}
            }},
            "nativeComponents":{},"modifiers":{"padding":{"parameters":[{"label":"_","type":"length","required":true}]}},
            "tokens":{"spacing":{"DesignSpacing.medium":"\(token)"},"radius":{},"font":{},"color":{}},
            "resources":{"namespace":"app","stringTable":"string","strings":{}}
          }
        }
        """
        return try Mapping.load(data: Data(text.utf8)).get()
    }

    private func diagnostics(_ data: Data) throws -> [Diagnostic] {
        switch Mapping.load(data: data) {
        case .success: return []
        case let .failure(error): return error.diagnostics
        }
    }
}
