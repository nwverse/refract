import RefractIR

extension ComposeBackend {
    func collectProjectedLists(_ bodies: [ViewNode]) -> [ListItems] {
        var result: [ListItems] = []
        func visit(_ node: ViewNode) {
            if case let .forEach(items, _) = node, items.projection != nil { result.append(items) }
            for child in node.children(for: .android) { visit(child) }
        }
        for body in bodies { visit(body) }
        return result
    }

    func emitCollectionProjections(_ items: [ListItems], into out: inout KotlinWriter) throws {
        for projection in Dictionary(grouping: items.compactMap(\.projection), by: \.name).keys.sorted() {
            guard let descriptor = items.compactMap(\.projection).first(where: { $0.name == projection }),
                  let list = items.first(where: { $0.projection?.name == projection }) else { continue }
            out.line()
            out.line("public fun \(descriptor.name)(")
            out.depth += 1
            out.line("items: List<\(list.itemType)>,")
            out.line("\(descriptor.categoryParameter): \(descriptor.categoryEnum)")
            out.depth -= 1
            out.open("): List<\(list.itemType)>")
            out.line("val filtered = items.filter { item ->")
            out.depth += 1
            out.line("\(descriptor.categoryParameter) == \(descriptor.categoryEnum).all || item.\(descriptor.categoryProperty) == \(descriptor.categoryParameter)")
            out.depth -= 1
            out.line("}")
            out.line("return filtered.sortedWith(Comparator { lhs, rhs ->")
            out.depth += 1
            out.line("val rank = lhs.\(descriptor.sortProperty).compareTo(rhs.\(descriptor.sortProperty))")
            out.line("if (rank != 0) \(descriptor.ascending ? "" : "-")rank else lhs.\(list.key).compareTo(rhs.\(list.key))")
            out.close(suffix: ")")
            out.close()
        }
    }

    func projectedCollectionExpression(_ items: ListItems, context: inout Context) throws -> String {
        guard let projection = items.projection else { return try renderExpression(items.collection, context: &context) }
        guard let source = sourceCollectionExpression(items),
              context.module.screens.contains(where: { $0.parameters.contains {
                  $0.name == projection.categoryParameter && $0.enumName == projection.categoryEnum
              } }), context.itemTypes.contains(where: { $0.name == items.itemType && $0.identity.type == .int }) else {
            throw Diagnostic(code: "RFLIST004", message: "The typed projection lacks its resolved source, category, or Int identity.",
                             suggestion: "Use the bounded filter/sort source form with an Int item id.", location: items.location)
        }
        let category = projection.categoryParameter
        context.imports.insert("androidx.compose.runtime.remember")
        return "remember(\(source), \(category)) { \(projection.name)(\(source), \(category)) }"
    }

    func sourceCollectionExpression(_ items: ListItems) -> String? {
        guard case let .valueProperty(.model(model, property)) = items.collection.value else { return nil }
        return "\(model).\(property).value"
    }
}
