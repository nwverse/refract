import RefractIR

extension ComposeBackend {
    /// Keep each message row and its surrounding source layout intact. Blocks are a bounded,
    /// non-scrolling part of that row, not sibling lazy items that disappear for empty messages.
    func emitMessageBlocks(_ nested: NestedListItems, into out: inout KotlinWriter,
                           context: inout Context) throws {
        let items = nested.items
        guard let parent = nested.parent, items.itemName != parent,
              items.itemType == "ChatBlock", items.key == "id", items.keyType == .string,
              case let .reference(collection) = items.collection.value, collection == "\(parent).blocks",
              case let .child(child, _) = items.content,
              child.arguments.contains(where: { $0.label == "message" && $0.expression == parent }),
              child.arguments.contains(where: { $0.label == "block" && $0.expression == items.itemName }) else {
            throw Diagnostic(code: "RFMSG001", message: "Message blocks require their checked ChatMessage parent and stable ChatBlock String ids.",
                             suggestion: "Use ForEach(message.blocks) with MessageBlock(message: message, block: block).",
                             location: items.location)
        }
        context.imports.insert("androidx.compose.foundation.layout.Column")
        context.imports.insert("androidx.compose.runtime.key")
        out.open("Column")
        out.line("\(parent).blocks.forEach { \(items.itemName) ->")
        out.depth += 1
        out.open("key(\(parent).id, \(items.itemName).id)")
        try emit(items.content, parentAxis: .vertical, into: &out, context: &context)
        out.close()
        out.depth -= 1
        out.line("}")
        out.close()
    }
}
