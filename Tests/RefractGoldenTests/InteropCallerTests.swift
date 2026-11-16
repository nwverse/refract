import Foundation
import Testing
import RefractGolden

/// The hand-written callers are part of the fixture, not decoration. Check their native entry-point contracts
/// while the golden runner checks the complete generated files they import.
@Test func nativeCallersUseTheGeneratedPublicEntryPoints() throws {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directory = repository.appendingPathComponent("Fixtures/interop-native-callers")
    let fixture = FixtureCase(
        name: "interop-native-callers", status: .ready,
        input: try String(contentsOf: directory.appendingPathComponent("Input.swift"), encoding: .utf8),
        mapping: nil,
        expectedKotlin: try String(contentsOf: directory.appendingPathComponent("Expected.kt"), encoding: .utf8),
        expectedArkTS: try String(contentsOf: directory.appendingPathComponent("Expected.ets"), encoding: .utf8),
        expectedDiagnostics: nil)
    let generated = try GoldenRunner.generate(fixture)
    let kotlin = try #require(generated.kotlin)
    let arkTS = try #require(generated.arkTS)
    #expect(kotlin.contains("public fun NativeCallerScreen(modifier: Modifier = Modifier)"))
    #expect(!kotlin.contains("import refract.runtime"))
    #expect(arkTS.contains("@ComponentV2\nexport struct NativeCallerScreen"))
    #expect(!arkTS.contains("@Entry"))

    let kotlinCaller = try String(contentsOf: directory.appendingPathComponent("NativeCaller.kt"), encoding: .utf8)
    let arkCaller = try String(contentsOf: directory.appendingPathComponent("NativeCaller.ets"), encoding: .utf8)
    #expect(kotlinCaller.contains("import refract.generated.NativeCallerScreen"))
    #expect(kotlinCaller.contains("NativeCallerScreen()"))
    #expect(arkCaller.contains("import { NativeCallerScreen } from './NativeCallerScreen';"))
    #expect(arkCaller.contains("NativeCallerScreen()"))
    #expect(!kotlinCaller.contains("RefractHost") && !arkCaller.contains("RefractHost"))
}
