import RefractIR
import RefractMapping

extension Generation {
    /// This is deliberately not LazyForEach: a bounded message row does not own a second scroll container.
    /// Its immutable blocks and stable block ids come from the app's ChatMessage snapshot.
    func emitMessageBlocks(_ nested: NestedListItems, into writer: inout ArkWriter,
                           parent: String?, location: RefractIR.SourceLocation?, mapping: Mapping,
                           resolver: InteropResolver?) throws {
        let items = nested.items
        guard let parentName = nested.parent ?? parent,
              parent != parentName, declaredItemInputs.contains(parentName), ArkText.isIdentifier(parentName),
              let parentArgument = nested.message,
              parentArgument.label == "message", parentArgument.expression == parentName,
              let blockArgument = nested.block,
              blockArgument.label == "block", blockArgument.expression == items.itemName,
              let message = itemTypes.first(where: { $0.name == "ChatMessage" }),
              message.messageProjection,
              let block = itemTypes.first(where: { $0.name == items.itemType }),
              block.name == "ChatBlock", block.messageProjection,
              items.itemName != parentName, items.key == "id", items.keyType == .string,
              items.modelType == nil,
              case let .reference(collection) = items.collection.value, collection == "\(parentName).blocks",
              case let .child(child, _) = items.content,
              child.item?.expression == items.itemName,
              child.arguments.contains(where: { $0.label == "message" && $0.expression == parentName }),
              child.arguments.contains(where: { $0.label == "block" && $0.expression == items.itemName }) else {
            throw Diagnostic(code: "RFMSG001",
                message: "A bounded ArkUI block ForEach requires a ChatMessage parent and stable ChatBlock String ids.",
                suggestion: "Use ForEach(message.blocks) with MessageBlock(message: message, block: block)",
                location: location)
        }
        let parentReceiver = "this.\(parentName)"
        writer.open("ForEach(\(parentReceiver).blocks, (\(items.itemName): ChatBlock) =>")
        let arguments = "message: \(parentReceiver), block: \(items.itemName)"
        writer.line("\(child.name)({ \(arguments) })")
        writer.close(suffix: ", (\(items.itemName): ChatBlock): string => \(items.itemName).id)")
    }
}
