import Foundation
import Testing
import RefractIR
import RefractMapping
import RefractCompose
import RefractArkUI
@testable import RefractFrontend

private let projectionFixtureURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/chat-message-projection")

private func projectionUnit(replacing old: String? = nil, with new: String = "") throws -> TranslationUnit {
    var input = try String(contentsOf: projectionFixtureURL.appendingPathComponent("Input.swift"), encoding: .utf8)
    if let old {
        #expect(input.contains(old))
        input = input.replacingOccurrences(of: old, with: new)
    }
    return Frontend.parse(SourceFile(path: "Input.swift", contents: input))
}

@Test func messageProjectionUsesCheckedIRAndNativeStableIdentities() throws {
    let unit = try projectionUnit()
    #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
    let message = try #require(unit.module.itemTypes.first { $0.name == "ChatMessage" })
    #expect(message.identity.type == .string)
    #expect(message.properties.map(\.name) == ["id", "revision", "blocks", "finalized"])
    #expect(message.properties[1].type == .revision)
    #expect(message.properties[2].collection?.itemType == "ChatBlock")
    let block = try #require(unit.module.itemTypes.first { $0.name == "ChatBlock" })
    #expect(block.identity.type == .string)
    let row = try #require(unit.module.screens.first { $0.name == "MessageRow" })
    guard case let .stack(_, children, _, _) = row.body,
          case let .messageBlocks(nested, _) = children[1] else {
        Issue.record("Expected one checked nested message block node")
        return
    }
    #expect(nested.items.collection.value == .reference("message.blocks"))
    #expect(nested.items.key == "id")
    #expect(nested.message?.expression == "message")
    #expect(nested.block?.expression == "block")

    let mapping = try Mapping.load(contentsOf: projectionFixtureURL.appendingPathComponent("refract.json"))
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("public val revision: Long"))
    #expect(kotlin.contains("public val blocks: List<ChatBlock>"))
    #expect(kotlin.contains("items = model.messages.value,"))
    #expect(kotlin.contains("key = { message -> message.id }"))
    #expect(kotlin.contains("message.blocks.forEach { block ->"))
    #expect(kotlin.contains("key(message.id, block.id)"))
    #expect(!kotlin.contains("refractMessageRows"))
    #expect(!kotlin.contains("LazyListScope"))
    #expect(kotlin.contains("if (message.finalized)"))
    #expect(kotlin.contains("MessageBlock(message = message, block = block)"))
    #expect(!kotlin.contains("LazyColumn(modifier = Modifier) {\n                    LazyColumn"))
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("@Trace revision: bigint;"))
    #expect(ark.contains("@Trace blocks: ChatBlock[];"))
    #expect(ark.contains("ForEach(this.message.blocks, (block: ChatBlock) =>"))
    #expect(ark.contains("MessageBlock({ message: this.message, block: block })"))
    #expect(ark.contains("(block: ChatBlock): string => block.id"))
}

@Test(arguments: [
    ("let revision: UInt64", "let revision: Int"),
    ("let revision: UInt64", "let revision: Int64"),
    ("let blocks: [ChatBlock]", "let blocks: [String]"),
    ("let finalized: Bool", "let finalized: Int"),
    ("let id: String\n    let text: String", "let id: Int\n    let text: String"),
    ("ForEach(message.blocks)", "ForEach(model.messages)"),
])
func messageProjectionRejectsInvalidSource(replacement: String, with new: String) throws {
    // Source replacements intentionally test whole declaration/collection shapes, not native runtime inputs.
    let unit = try projectionUnit(replacing: replacement, with: new)
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.contains { $0.code == "RFMSG001" },
            Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
}

@Test func messageProjectionPreservesTheCompleteParentRowIncludingEmptyMessages() throws {
    let unit = try projectionUnit(replacing: "List(model.messages) { message in\n            MessageRow(message: message)\n        }",
                                  with: "List { ForEach(model.messages) { message in\n            MessageRow(message: message)\n        } }")
    #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
    let kotlin = try ComposeBackend().generate(module: unit.module)
    #expect(kotlin.contains("items = model.messages.value,"))
    #expect(kotlin.contains("MessageRow(message = message)"))
    #expect(kotlin.contains("message.blocks.forEach { block ->"))
    #expect(!kotlin.contains("chatMessage.blocks.isEmpty"))
    #expect(!kotlin.contains("refractMessageRows"))
    #expect(!kotlin.contains("LazyListScope"))
    let title = try #require(kotlin.range(of: "Text(text = message.id)"))
    let blocks = try #require(kotlin.range(of: "message.blocks.forEach { block ->"))
    #expect(title.lowerBound < blocks.lowerBound)
}

@Test func messageProjectionKeepsNonBlockContentInSourceOrder() throws {
    let unit = try projectionUnit()
    #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
    let kotlin = try ComposeBackend().generate(module: unit.module)
    let blocks = try #require(kotlin.range(of: "message.blocks.forEach { block ->"))
    let after = try #require(kotlin.range(of: "Text(text = \"Row footer\")"))
    #expect(blocks.lowerBound < after.lowerBound)
}

@Test func messageProjectionSupportsSplitDeclarationFilesAndSiblingParameters() throws {
    let input = try String(contentsOf: projectionFixtureURL.appendingPathComponent("Input.swift"), encoding: .utf8)
    let marker = "protocol ConversationModel: RefractModel {"
    let parts = input.components(separatedBy: marker)
    #expect(parts.count == 2)
    let declarations = parts[0]
    let rest = marker + parts[1]
    let screens = rest.components(separatedBy: "struct ConversationScreen: View {")
    #expect(screens.count == 2)
    let sources = [
        SourceFile(path: "ChatMessage.swift", contents: "import SwiftUI\n" + declarations),
        SourceFile(path: "MessageRow.swift", contents: "import SwiftUI\n" + screens[0]),
        SourceFile(path: "ConversationScreen.swift", contents: "import SwiftUI\nstruct ConversationScreen: View {" + screens[1]),
    ]
    let units = Frontend.parse(sources: sources)
    for unit in units {
        #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
    }
    let nativeSources = NativeSourceSet(modules: units.map(\.module))
    for unit in units {
        let kotlin = try ComposeBackend().generate(module: unit.module, sources: nativeSources)
        #expect(!kotlin.contains("refractMessageRows"))
        #expect(!kotlin.contains("LazyListScope"))
        if unit.module.screens.contains(where: { $0.name == "MessageRow" }) {
            #expect(kotlin.contains("message.blocks.forEach { block ->"))
            #expect(kotlin.contains("key(message.id, block.id)"))
        }
    }
    let conversation = try #require(units.last)
    let kotlin = try ComposeBackend().generate(module: conversation.module, sources: nativeSources)
    #expect(kotlin.contains("items = model.messages.value,"))
    #expect(kotlin.contains("MessageRow(message = message)"))
}

@Test func doubleActionsStillAcceptIntegerLiterals() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel { func setZoom(_ value: Double) }
    struct Screen: View {
        let model: Model
        var body: some View { Button { model.setZoom(1) } label: { Text(verbatim: "Zoom") } }
    }
    """))
    #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
    let kotlin = try ComposeBackend().generate(module: unit.module)
    #expect(kotlin.contains("model.setZoom(1)"))
}

@Test func messageProjectionRejectsInvalidBlockChildInputs() throws {
    let unit = try projectionUnit(replacing: "MessageBlock(message: message, block: block)",
                                  with: "MessageBlock(message: block, block: message)")
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.contains { $0.code == "RFMSG001" })
}

@Test func ordinaryBooleanModelConditionsKeepTheirExistingLowering() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel { var enabled: Bool { get } }
    struct Screen: View {
        let model: Model
        var body: some View {
            VStack {
                if model.enabled { Text(verbatim: "Enabled") }
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
    let output = try ComposeBackend().generate(module: unit.module)
    #expect(output.contains("if (model.enabled.value)"))
}

@Test func messageProjectionRejectsOrdinaryNestedDynamicRows() throws {
    let unit = try projectionUnit(replacing: "ForEach(message.blocks) { block in",
                                  with: "ForEach(model.messages) { block in")
    #expect(unit.diagnostics.contains { $0.code == "RFMSG001" })
}
