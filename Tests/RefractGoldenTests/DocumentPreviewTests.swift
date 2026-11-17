import Foundation
import Testing
import RefractArkUI
import RefractCompose
import RefractGolden
import RefractIR

private func documentPreviewFixture() throws -> FixtureCase {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directory = repository.appendingPathComponent("Fixtures/interop-document-preview")
    return FixtureCase(
        name: "interop-document-preview", status: .ready,
        input: try String(contentsOf: directory.appendingPathComponent("Input.swift"), encoding: .utf8),
        mapping: try String(contentsOf: directory.appendingPathComponent("refract.json"), encoding: .utf8),
        expectedKotlin: try String(contentsOf: directory.appendingPathComponent("Expected.kt"), encoding: .utf8),
        expectedArkTS: try String(contentsOf: directory.appendingPathComponent("Expected.ets"), encoding: .utf8),
        expectedDiagnostics: nil)
}

@Test func documentPreviewPreservesMetadataActionsAndEveryTerminalState() throws {
    let generated = try GoldenRunner.generate(documentPreviewFixture())
    let kotlin = try #require(generated.kotlin)
    let arkTS = try #require(generated.arkTS)
    #expect(generated.diagnostics.isEmpty)
    #expect(kotlin.contains("NativeDocumentPreview(uri = uri, displayName = displayName, mimeType = mimeType, byteCount = byteCount, revision = revision, onClose = { model.closePreview() })"))
    #expect(arkTS.contains("onClose: () => { this.model.closePreview(); }"))
    for state in ["loading", "ready", "missing", "unsupported", "cancelled", "closed"] {
        #expect(kotlin.contains("DocumentPreviewState.\(state)"))
        #expect(arkTS.contains("DocumentPreviewState.\(state)"))
    }
    for forbidden in ["WebView", "java.net.", "http://", "https://", "refract.runtime"] {
        #expect(!kotlin.contains(forbidden))
        #expect(!arkTS.contains(forbidden))
    }
}

@Test func nativeActionRoundTripsWithoutBecomingAScalar() throws {
    let action = StateAction.modelMethod(model: "model", name: "closePreview", arguments: [])
    let argument = NativeArgument(label: "onClose", action: action, type: .action)
    let data = try JSONEncoder().encode(argument)
    #expect(try JSONDecoder().decode(NativeArgument.self, from: data) == argument)
    #expect(NativeParameterType.action.scalar == nil)
}
