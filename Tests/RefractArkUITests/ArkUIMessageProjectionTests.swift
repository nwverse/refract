import Foundation
import Testing
import RefractArkUI
import RefractFrontend
import RefractIR

private let messageProjectionFixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/chat-message-projection/Input.swift")

@Test func arkUIMessageBlocksUseTheDeclaredParentReceiver() throws {
    let input = try String(contentsOf: messageProjectionFixture, encoding: .utf8)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input))
    #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))

    let output = try ArkUIBackend().generate(module: unit.module)
    #expect(output.contains("@Param @Require public var message: ChatMessage"))
    #expect(output.contains("ForEach(this.message.blocks, (block: ChatBlock) => {"))
    #expect(output.contains("MessageBlock({ message: this.message, block: block })"))
    #expect(output.contains("(block: ChatBlock): string => block.id"))
    #expect(!output.contains("ForEach(message.blocks"))
    #expect(!output.contains("MessageBlock({ message: message, block: block })"))
}

@Test func arkUIMessageBlocksRejectAnUncheckedParentArgument() {
    let block = ItemType(name: "ChatBlock", identity: ItemProperty(name: "id", type: .string), properties: [
        ItemProperty(name: "id", type: .string),
        ItemProperty(name: "text", type: .string),
    ], messageProjection: true)
    let message = ItemType(name: "ChatMessage", identity: ItemProperty(name: "id", type: .string), properties: [
        ItemProperty(name: "id", type: .string),
        ItemProperty(name: "revision", type: .revision),
        ItemProperty(name: "blocks", type: .string,
                     collection: ItemCollection(itemType: "ChatBlock", owner: "ChatMessage", property: "blocks")),
        ItemProperty(name: "finalized", type: .bool),
    ], messageProjection: true)
    let items = ListItems(collection: Expression(.reference("message.blocks")), itemName: "block", itemType: "ChatBlock",
                          keyType: .string,
                          content: .child(ChildView(name: "MessageBlock", arguments: [
                            ChildView.Argument(label: "message", expression: "message"),
                            ChildView.Argument(label: "block", expression: "block"),
                          ]), location: nil))
    let nested = NestedListItems(items, parent: "message",
                                 message: ChildView.Argument(label: "message", expression: "unrelated"),
                                 block: ChildView.Argument(label: "block", expression: "block"))
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "MessageRow",
               parameters: [ScreenParameter(name: "message", type: .string, itemType: "ChatMessage")],
               body: .messageBlocks(nested, location: nil)),
    ], itemTypes: [message, block])

    let diagnostic = #expect(throws: Diagnostic.self) {
        try ArkUIBackend().generate(module: module)
    }
    #expect(diagnostic?.code == "RFMSG001")
}
