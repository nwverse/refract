import Foundation
import Testing
import RefractIR
import RefractMapping
import RefractFrontend
@testable import RefractCompose
import RefractArkUI

private func selectionMapping() throws -> Mapping {
    try Mapping.load(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/selection-link-context/refract.json"))
}

private func selectionSource(content: String = #"RefractSelectionContent(text: "读 🌸 docs", links: [RefractSelectionLink(range: RefractSelectionRange(start: 5, end: 9), destination: "https://example.test/docs")])"#,
                             callback: String = #"model.useAsContext(start: context.range.start, end: context.range.end, text: context.text)"#) -> SourceFile {
    SourceFile(path: "Input.swift", contents: """
    protocol SelectionMessageModel: RefractModel {
        func openLink(_ destination: String)
        func useAsContext(start: Int, end: Int, text: String)
        func editWithAI(start: Int, end: Int, text: String)
    }
    struct NativeSelectionMessage: RefractNativeView {
        let content: RefractSelectionContent
        let onLink: (String) -> Void
        let onUseAsContext: (RefractSelectionContext) -> Void
        let onEditWithAI: (RefractSelectionContext) -> Void
        var body: some View { Text(verbatim: content.text) }
    }
    struct SelectionMessageScreen: View {
        let model: SelectionMessageModel
        var body: some View {
            NativeSelectionMessage(content: \(content),
                onLink: { destination in model.openLink(destination) },
                onUseAsContext: { context in \(callback) },
                onEditWithAI: { context in model.editWithAI(start: context.range.start, end: context.range.end, text: context.text) })
        }
    }
    """)
}

@Test func literalSelectionEmitsTypedHostAndModelSnapshots() throws {
    let unit = Frontend.parse(selectionSource())
    #expect(unit.diagnostics.isEmpty)
    let mapping = try selectionMapping()
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("RefractSelectionRange(start = 5, end = 9)"))
    #expect(kotlin.contains("model.useAsContext(start = context.range.start, end = context.range.end, text = context.text)"))
    #expect(kotlin.contains("model.openLink(destination)"))
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("new RefractSelectionRange(5, 9)"))
    #expect(ark.contains("RefractSelectionContent, RefractSelectionContext, RefractSelectionLink, RefractSelectionRange"))
    #expect(ark.contains("this.model.editWithAI(context.range.start, context.range.end, context.text);"))
}

@Test(arguments: [
    #"RefractSelectionContent(text: "🌸", links: [RefractSelectionLink(range: RefractSelectionRange(start: 1, end: 2), destination: "https://example.test")])"#,
    #"RefractSelectionContent(text: "abc", links: [RefractSelectionLink(range: RefractSelectionRange(start: 1, end: 1), destination: "https://example.test")])"#,
    #"RefractSelectionContent(text: "abcdef", links: [RefractSelectionLink(range: RefractSelectionRange(start: 0, end: 3), destination: "https://example.test"), RefractSelectionLink(range: RefractSelectionRange(start: 2, end: 4), destination: "https://example.test/two")])"#,
    #"RefractSelectionContent(text: "abc", links: [RefractSelectionLink(range: RefractSelectionRange(start: 0, end: 3), destination: "http://example.test")])"#,
])
func invalidSelectionRangesAndDestinationsAreDiagnostics(content: String) {
    let unit = Frontend.parse(selectionSource(content: content))
    #expect(unit.diagnostics.contains { $0.code.hasPrefix("RFSELECTION") })
}

@Test func selectionRejectsSnapshotMutation() {
    let unit = Frontend.parse(selectionSource(callback: #"model.useAsContext(start: 0, end: 0, text: "changed")"#))
    #expect(unit.diagnostics.contains { $0.code == "RFSELECTION006" })
}

@Test func selectionRejectsDynamicProjectedContentAndArbitraryCallbacks() {
    let dynamic = selectionSource(content: "message")
    #expect(Frontend.parse(dynamic).diagnostics.contains { $0.code == "RFSELECTION001" })
    let arbitrary = selectionSource(callback: #"model.openLink("https://example.test")"#)
    #expect(Frontend.parse(arbitrary).diagnostics.contains { $0.code == "RFSELECTION006" })
}

@Test(arguments: [
    "let content: RefractSelectionContent",
    "let onLink: (String) -> Void",
    "let onOpen: (String) -> Void",
    "let onUseAsContext: (RefractSelectionContext) -> Void",
    "let onEditWithAI: (RefractSelectionContext) -> Void",
    """
    let content: RefractSelectionContent
    let onOpen: (String) -> Void
    let onUseAsContext: (RefractSelectionContext) -> Void
    let onEditWithAI: (RefractSelectionContext) -> Void
    """,
    """
    let onLink: (String) -> Void
    let content: RefractSelectionContent
    let onUseAsContext: (RefractSelectionContext) -> Void
    let onEditWithAI: (RefractSelectionContext) -> Void
    """,
    """
    let content: RefractSelectionContent
    let onLink: (String) -> Void
    let onUseAsContext: (RefractSelectionContext) -> Void
    let onEditWithAI: (RefractSelectionContext) -> Void
    let extra: String
    """,
])
func selectionTypesOutsideTheCompleteLiteralHostAreDiagnostics(_ declaration: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct UnboundedSelection: RefractNativeView {
        \(declaration)
        var body: some View { Text(verbatim: "Synthetic") }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE001"])
    guard let diagnostic = unit.diagnostics.first else { return }
    #expect(diagnostic.message.contains("literal-selection host"))
    #expect(diagnostic.suggestion?.contains("content") == true)
    #expect(diagnostic.location?.line == 1)
    #expect(diagnostic.location?.column == 8)
}

@Test(arguments: [
    "let onRequest: (String) -> Void\n    let onConfirm: (String) -> Void",
    "let onRequest: (String) -> Void",
    "let onConfirm: (String) -> Void",
])
func swipeDeclarationCannotBypassLiteralSelectionRestriction(_ callback: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct NativeSwipeArchiveRow: RefractNativeView {
        \(callback)
        var body: some View { Text(verbatim: "Synthetic") }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE001"])
    #expect(unit.diagnostics.first?.message.contains("literal-selection host") == true)
}

@Test func selectionContentRoundTripsLiteralUnicodeAndEmptyRange() throws {
    let content = SelectionContent(text: "🌸", links: [
        SelectionLink(range: SelectionRange(start: 0, end: 2), destination: "https://example.test"),
    ])
    let decoded = try JSONDecoder().decode(SelectionContent.self,
        from: JSONEncoder().encode(content))
    #expect(decoded == content)
    #expect(decoded.text.utf16.count == 2)
    #expect(SelectionRange(start: 2, end: 2).start == 2)
    let argument = NativeArgument(label: "content", selection: content, type: .selectionContent)
    let decodedArgument = try JSONDecoder().decode(NativeArgument.self,
        from: JSONEncoder().encode(argument))
    #expect(decodedArgument == argument)
}
