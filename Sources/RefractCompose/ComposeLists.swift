import RefractIR

extension ComposeBackend {
    /// Resolves identity and observation before emitting a lazy native collection.
    /// An invalid model or item declaration is never replaced by an eager row loop.
    func dynamicListItems(_ items: ListItems, context: inout Context) throws {
        guard case let .valueProperty(.model(model, property)) = items.collection.value,
              let owner = items.modelType,
              context.models.contains(where: { $0.name == owner }),
              context.module.screens.contains(where: { screen in
                  screen.states.contains { state in
                      if case let .model(reference, _) = state {
                          return reference.propertyName == model && reference.protocolName == owner
                      }
                      return false
                  }
              }) else {
            throw Diagnostic(code: "RFLIST001",
                             message: "A dynamic List requires an observable model collection with typed item identity.",
                             suggestion: "Use a RefractModel collection of Identifiable items with a stable String or Int id.",
                             location: items.location ?? items.collection.location)
        }
        guard let reference = context.models.first(where: { $0.name == owner }),
              let modelProperty = reference.properties.first(where: { $0.name == property }),
              let collection = modelProperty.collection,
              collection.itemType == items.itemType,
              collection.key == items.key,
              collection.keyType == items.keyType else {
            throw Diagnostic(code: "RFLIST001",
                             message: "The List collection has no resolved observable identity contract.",
                             suggestion: "Expose the collection through a declared RefractModel interface and a stored String or Int id.",
                             location: items.location ?? items.collection.location)
        }
        guard [.string, .int].contains(items.keyType) else {
            throw Diagnostic(code: "RFLIST001",
                             message: "List identity must be a stored String or Int property.",
                             suggestion: "Use Identifiable with a stable stored String or Int id.",
                             location: items.location)
        }
        guard context.itemTypes.contains(where: {
            $0.name == items.itemType && $0.identity.name == items.key && $0.identity.type == items.keyType
        }) else {
            throw Diagnostic(code: "RFLIST001",
                             message: "List item `\(items.itemType)` has no matching stored identity declaration.",
                             suggestion: "Declare an Identifiable item with a stored String or Int id.",
                             location: items.location)
        }
        // `model` is deliberately validated by the expression path at the leaf; the model's
        // collection descriptor is what makes this a State<List<Item>>, not an untyped array.
        _ = model
        _ = reference
    }

    func emitDynamicListItems(_ items: ListItems, into out: inout KotlinWriter,
                              context: inout Context) throws {
        try dynamicListItems(items, context: &context)
        if items.messageBlocks != nil {
            try emitMessageRows(items, into: &out, context: &context)
            return
        }
        let collection = try renderExpression(items.collection, context: &context)
        let item = items.itemName
        let key = "\(item).\(items.key)"
        out.open("items(")
        out.line("items = \(collection),")
        out.line("key = { \(item) -> \(key) },")
        if let contentType = items.contentType {
            guard case let .child(child, _) = items.content, child.contentType == contentType else {
                throw Diagnostic(code: "RFNATIVE004", message: "A row content type must belong to the direct generated child row.",
                                 suggestion: "Apply `.refractNativeModifier(.contentType(\"setting\"))` to the child call", location: items.location)
            }
        }
        out.line("contentType = { \"\(items.contentType ?? items.itemType)\" },")
        out.depth -= 1
        out.line(") { \(item) ->")
        out.depth += 1
        let previousItem = context.retainedItem
        context.retainedItem = (items.itemName, items.itemType)
        defer { context.retainedItem = previousItem }
        try emit(items.content, parentAxis: .vertical, into: &out, context: &context)
        out.close()
    }
}
