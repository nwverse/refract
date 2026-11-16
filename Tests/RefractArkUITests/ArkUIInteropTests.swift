import Foundation
import Testing
@testable import RefractArkUI
@testable import RefractFrontend
import RefractIR
import RefractMapping

@Test func arkUIMatchesNativeComponentGolden() throws {
    let generated = try generateInteropFixture("interop-native-component")
    let expected = try String(contentsOf: fixture("interop-native-component/Expected.ets"), encoding: .utf8)
    #expect(generated == expected)
}

@Test func arkUISelectsHarmonyPlatformValueAndView() throws {
    let value = try generateInteropFixture("interop-platform-value")
    #expect(value.contains(".padding(16)"))
    #expect(value.contains("Text('HarmonyOS')"))
    #expect(!value.contains("Android") && !value.contains("iOS"))

    let view = try generateInteropFixture("interop-platform-view")
    #expect(view.contains("Text('Status')"))
    #expect(view.contains(".padding(16)"))
    #expect(!view.contains("Text(\"Android\")") && !view.contains("Text(\"iOS\")"))
}

@Test func arkUIValidatesNativeMappingsBeforeOutput() throws {
    let directory = fixture("interop-native-component")
    let input = try String(contentsOf: directory.appendingPathComponent("Input.swift"), encoding: .utf8)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input))
    #expect(unit.diagnostics.isEmpty)
    #expect(throws: (any Error).self) {
        try ArkUIBackend().generate(module: unit.module, mapping: .empty)
    }
}

private func generateInteropFixture(_ name: String) throws -> String {
    let directory = fixture(name)
    let input = try String(contentsOf: directory.appendingPathComponent("Input.swift"), encoding: .utf8)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input))
    #expect(unit.diagnostics.isEmpty)
    let mappingPath = directory.appendingPathComponent("refract.json")
    let mapping = FileManager.default.fileExists(atPath: mappingPath.path)
        ? try Mapping.load(contentsOf: mappingPath) : .empty
    return try ArkUIBackend().generate(module: unit.module, mapping: mapping)
}

private func fixture(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
}
