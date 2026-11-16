import Foundation
import Testing
import RefractGolden
import RefractMapping
import RefractFrontend
import RefractIR
import RefractCompose
import RefractArkUI

@Test func typedLayoutUsesBothNativeCatalogs() throws {
    let fixture = try #require(CorpusLoader.load(repository: GoldenTests.repository).first {
        $0.name == "compose-typed-layout"
    })
    #expect(fixture.resourceBaseURL?.lastPathComponent == "compose-typed-layout")
    let mapping = try Mapping.load(data: Data(fixture.mapping!.utf8), file: "refract.json",
                                   resourceBaseURL: fixture.resourceBaseURL)
    #expect(mapping.harmonyOS.resources.stringTable == "string")
    #expect(mapping.harmonyOS.resources.catalog == "resources/base/element/string.json")
    #expect(try mapping.stringResource("settings.profile", platform: .harmonyOS).nativeName == "settings_profile")
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: fixture.input))
    #expect(unit.diagnostics.isEmpty)
    _ = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    _ = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    try LocalizationResourceValidator.validate(module: unit.module, mapping: mapping)
    let result = try GoldenRunner.generate(fixture)
    #expect(result.diagnostics.isEmpty)
    #expect(GoldenRunner.differences(for: fixture, result: result) == [])
}
