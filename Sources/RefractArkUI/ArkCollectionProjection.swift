import RefractIR

extension Generation {
    func collectProjectedLists(_ bodies: [ViewNode]) -> [ListItems] {
        var result: [ListItems] = []
        func visit(_ node: ViewNode) {
            if case let .forEach(items, _) = node, items.projection != nil { result.append(items) }
            for child in node.children(for: .harmonyOS) { visit(child) }
        }
        for body in bodies { visit(body) }
        return result
    }

    func emitCollectionProjections(_ lists: [ListItems], into writer: inout ArkWriter) throws {
        for name in Dictionary(grouping: lists.compactMap(\.projection), by: \.name).keys.sorted() {
            guard let list = lists.first(where: { $0.projection?.name == name }),
                  let projection = list.projection else { continue }
            writer.line()
            writer.line("export function \(projection.name)(items: \(list.itemType)[], \(projection.categoryParameter): \(projection.categoryEnum)): \(list.itemType)[] {")
            writer.depth += 1
            writer.line("const filtered = items.filter((item: \(list.itemType)): boolean =>")
            writer.depth += 1
            writer.line("\(projection.categoryParameter) === \(projection.categoryEnum).all || item.\(projection.categoryProperty) === \(projection.categoryParameter));")
            writer.depth -= 1
            writer.open("return filtered.sort((lhs: \(list.itemType), rhs: \(list.itemType)): number =>")
            writer.line("if (lhs.\(projection.sortProperty) !== rhs.\(projection.sortProperty)) {")
            writer.depth += 1
            writer.line("return lhs.\(projection.sortProperty) \(projection.ascending ? "<" : ">") rhs.\(projection.sortProperty) ? 1 : -1;")
            writer.depth -= 1
            writer.line("}")
            writer.line("return lhs.\(list.key) < rhs.\(list.key) ? -1 : 1;")
            writer.close(suffix: ");")
            writer.depth -= 1
            writer.line("}")
        }
    }
}
