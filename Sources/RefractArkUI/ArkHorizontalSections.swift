import RefractIR
import RefractMapping

extension Generation {
    func emitHorizontalSections(_ sections: HorizontalSectionCollection, into writer: inout ArkWriter,
                                mapping: Mapping, resolver: InteropResolver?) throws {
        guard case let .valueProperty(.model(_, property)) = sections.collection.value,
              let owner = module.models.first(where: { $0.name == sections.modelType }),
              owner.properties.contains(where: { $0.name == property && $0.collection != nil }),
              let sectionType = itemTypes.first(where: { $0.name == sections.sectionType }),
              sectionType.identity.name == sections.sectionKey,
              sectionType.identity.type == sections.sectionKeyType,
              [.string, .int].contains(sections.sectionKeyType) else {
            throw Diagnostic(code: "RFLIST004",
                message: "ArkUI horizontal sections need an identified model-owned section collection.",
                suggestion: "Expose the section collection through the declared RefractModel.",
                location: sections.location)
        }
        let source = try ArkExpression.emit(sections.collection, mapping: mapping)
        guard let itemType = itemTypes.first(where: { $0.name == sections.rows.itemType }),
              itemType.identity.name == sections.rows.key,
              itemType.identity.type == sections.rows.keyType,
              sectionType.properties.contains(where: { $0.name == sections.titleProperty && $0.type == .string }),
              [.string, .int].contains(sections.rows.keyType) else {
            throw Diagnostic(code: "RFLIST004",
                message: "ArkUI horizontal sections require matching stored section/item String or Int identities.",
                suggestion: "Use one identified section item collection with a declared String title property.",
                location: sections.rows.location)
        }
        writer.open("LazyForEach(\(source), (\(sections.sectionName): \(sections.sectionType)) =>")
        writer.open("ListItemGroup({ header: Text(\(sections.sectionName).\(sections.titleProperty)) })")
        writer.open("ListItem()")
        writer.open("LazyRow(Scroller())")
        writer.open("ForEach(\(sections.sectionName).\(sections.rows.property), (\(sections.rows.itemName): \(sections.rows.itemType)) =>")
        try emit(sections.rows.content, into: &writer, item: sections.rows.itemName,
                 mapping: mapping, resolver: resolver, itemTypeName: sections.rows.itemType)
        let key = "\(sections.rows.itemName).\(sections.rows.key)"
        writer.close(suffix: ", (\(sections.rows.itemName): \(sections.rows.itemType)): string => \(sections.rows.keyType == .int ? "String(\(key))" : key))")
        writer.close()
        writer.close()
        writer.close()
        let sectionKey = "\(sections.sectionName).\(sections.sectionKey)"
        writer.close(suffix: ", (\(sections.sectionName): \(sections.sectionType)): string => \(sections.sectionKeyType == .int ? "String(\(sectionKey))" : sectionKey))")
    }
}
