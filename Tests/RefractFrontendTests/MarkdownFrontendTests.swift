import Foundation
import Testing
import RefractFrontend
import RefractIR
import RefractMapping
import RefractCompose
import RefractArkUI

@Test func typedMarkdownPreservesStructureAndAppOwnedLinkAction() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let fixture = root.appendingPathComponent("Fixtures/markdown-conversation")
    let source = try String(contentsOf: fixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    let mapping = try Mapping.load(contentsOf: fixture.appendingPathComponent("refract.json"))
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source), mapping: mapping)
    #expect(unit.diagnostics.isEmpty)
    guard case let .markdown(document, action, _, _)? = unit.module.screens.first?.body.children.first else {
        Issue.record("The one Swift AST must reach the shared IR, not a native mapping or string payload")
        return
    }
    #expect(document.version == 1)
    #expect(document.blocks.map(\.stableID) == ["answer.summary", "answer.example"])
    #expect(action == MarkdownLinkAction(model: "model", method: "openLink"))
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("LinkAnnotation.Url("))
    #expect(kotlin.contains("model.openLink(\"https://example.com/docs\")"))
    #expect(kotlin.contains("FontFamily.Monospace"))
    #expect(kotlin.contains("key(\"answer.summary\")"))
    #expect(!kotlin.contains("WebView"))
    #expect(!kotlin.contains("markdownParser"))
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("Span('let answer = 42')"))
    #expect(ark.contains("this.model.openLink('https://example.com/docs');"))
    #expect(!ark.contains("RichEditor"))
    #expect(!ark.contains("Any"))
}

@Test func markdownRejectsWrongLinkSignatureAndDuplicateIdentity() {
    let wrongAction = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol BadModel: RefractModel { func openLink(_ value: Int) }
    struct BadMarkdown: View {
        let model: BadModel
        var body: some View {
            refractMarkdown(version: 1, blocks: [
                .paragraph(id: "answer.one", content: [.localized("conversation.answer")]),
            ], onLink: .linkAction(model.openLink))
        }
    }
    """))
    #expect(wrongAction.diagnostics.map(\.code).contains("RFMD017"))
    let duplicate = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol GoodModel: RefractModel { func openLink(_ url: String) }
    struct DuplicateMarkdown: View {
        let model: GoodModel
        var body: some View {
            refractMarkdown(version: 1, blocks: [
                .paragraph(id: "answer.same", content: [.localized("conversation.answer")]),
                .paragraph(id: "answer.same", content: [.localized("conversation.answer")]),
            ], onLink: .linkAction(model.openLink))
        }
    }
    """))
    #expect(duplicate.diagnostics.map(\.code).contains("RFMD006"))
}
