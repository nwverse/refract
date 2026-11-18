import RefractIR

extension ComposeBackend {
    /// Preserve the Swift row order: a meaningful parent container precedes its bounded blocks.
    /// Blocks are appended in the LazyColumn builder, not in the parent's composable content.
    func emitMessageRows(_ items: ListItems, into out: inout KotlinWriter,
                         context: inout Context) throws {
        guard let nested = items.messageBlocks else {
            try emitDynamicListItems(items, into: &out, context: &context)
            return
        }
        guard items.itemType == "ChatMessage", items.keyType == .string,
              case let .valueProperty(.model(_, _)) = items.collection.value,
              case let .child(_, _) = nested.content else {
            throw Diagnostic(code: "RFMSG001", message: "Message projection requires typed message and block content.")
        }
        let messages = try renderExpression(items.collection, context: &context)
        // Parent layout is meaningful only when it presents blocks. An empty snapshot contributes no empty row.
        out.open("refractMessageRows(")
        out.line("messages = \(messages),")
        out.line("messageContent = { message ->")
        out.depth += 1
        try emit(items.content, parentAxis: .vertical, into: &out, context: &context)
        out.depth -= 1
        out.line("},")
        out.line("blockContent = { message, block ->")
        out.depth += 1
        if case let .child(child, _) = nested.content {
            out.line("\(child.name)(message = message, block = block)")
        }
        out.depth -= 1
        out.line("},")
        out.depth -= 1
        out.line(")")
    }
}

func emitComposeMessageKey(into out: inout KotlinWriter) {
    out.line()
    out.line("internal fun refractMessageBlockKey(messageID: String, blockID: String): String {")
    out.depth += 1
    out.line("return \"${messageID.length}:$messageID${blockID.length}:$blockID\"")
    out.close()
    out.line()
    out.open("internal fun LazyListScope.refractMessageRows(")
    out.line("messages: List<ChatMessage>,")
    out.line("messageContent: @Composable (ChatMessage) -> Unit,")
    out.line("blockContent: @Composable (ChatMessage, ChatBlock) -> Unit,")
    out.depth -= 1
    out.line(") {")
    out.depth += 1
    out.open("for (chatMessage in messages)")
    out.line("if (chatMessage.blocks.isEmpty()) continue")
    out.line("item(key = chatMessage.id, contentType = \"ChatMessage\") {")
    out.depth += 1
    out.line("messageContent(chatMessage)")
    out.depth -= 1
    out.line("}")
    out.open("items(")
    out.line("items = chatMessage.blocks,")
    out.line("key = { block -> refractMessageBlockKey(chatMessage.id, block.id) },")
    out.line("contentType = { \"ChatBlock\" },")
    out.depth -= 1
    out.line(") { block ->")
    out.depth += 1
    out.line("blockContent(chatMessage, block)")
    out.close()
    out.close()
    out.close()
}

func containsMessageBlocks(_ bodies: [ViewNode]) -> Bool {
    func contains(_ node: ViewNode) -> Bool {
        if case let .forEach(items, _) = node, items.messageBlocks != nil { return true }
        if case .list = node { return false }
        if case .messageBlocks = node { return true }
        return node.children(for: .android).contains(where: contains)
    }
    return bodies.contains(where: contains)
}
