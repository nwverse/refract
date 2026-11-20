import RefractIR

extension ComposeBackend {
    func emitHorizontalSections(_ sections: HorizontalSectionCollection, isRoot: Bool,
                                into out: inout KotlinWriter, context: inout Context) throws {
        guard case let .valueProperty(.model(_, property)) = sections.collection.value,
              let owner = context.models.first(where: { $0.name == sections.modelType }),
              let collection = owner.properties.first(where: { $0.name == property })?.collection,
              collection.itemType == sections.sectionType,
              let sectionType = context.itemTypes.first(where: { $0.name == sections.sectionType }),
              sectionType.identity.name == sections.sectionKey, sectionType.identity.type == sections.sectionKeyType,
              let itemsProperty = sectionType.properties.first(where: { $0.name == sections.rows.property }),
              itemsProperty.collection?.itemType == sections.rows.itemType else {
            throw Diagnostic(code: "RFLIST004",
                message: "Horizontal sections require resolved section/item identities and model collection ownership.",
                suggestion: "Use identified sections with one identified horizontal item collection per section.",
                location: sections.location)
        }
        guard let itemType = context.itemTypes.first(where: { $0.name == sections.rows.itemType }),
              itemType.identity.name == sections.rows.key,
              sectionType.properties.contains(where: { $0.name == sections.titleProperty && $0.type == .string }),
              [.string, .int].contains(sections.sectionKeyType) else {
            throw Diagnostic(code: "RFLIST004",
                message: "Horizontal section and item identities must be declared stored String or Int ids.",
                suggestion: "Declare stable String or Int ids on both the section and its horizontal items.",
                location: sections.location)
        }
        let sectionSource = try renderExpression(sections.collection, context: &context)
        let section = sections.sectionName
        let item = sections.rows.itemName
        context.imports.insert("androidx.compose.foundation.lazy.LazyColumn")
        context.imports.insert("androidx.compose.ui.platform.testTag")
        out.open("LazyColumn(modifier = \(try modifierChain([], isRoot: isRoot, into: &out, context: &context)).testTag(\"refract_horizontal_sections\"))")
        out.open("items(")
        out.line("items = \(sectionSource),")
        out.line("key = { \(section) -> \"section:\" + \(section).\(sections.sectionKey) },")
        out.line("contentType = { \"HorizontalSection\" },")
        out.closeParenAndOpenBody(section)
        out.line("val \(section)HorizontalState = rememberSaveable(saver = LazyListState.Saver) { LazyListState() }")
        context.imports.insert("androidx.compose.foundation.layout.Column")
        context.imports.insert("androidx.compose.foundation.lazy.LazyListState")
        context.imports.insert("androidx.compose.runtime.saveable.rememberSaveable")
        out.open("Column")
        context.imports.insert("androidx.compose.material3.Text")
        out.line("Text(text = \(section).\(sections.titleProperty))")
        context.imports.insert("androidx.compose.foundation.lazy.LazyRow")
        context.imports.insert("androidx.compose.foundation.lazy.items")
        out.open("LazyRow(state = \(section)HorizontalState, modifier = Modifier.testTag(\"refract_horizontal_section_\" + \(section).\(sections.sectionKey)))")
        out.open("items(")
        out.line("items = \(section).\(sections.rows.property),")
        out.line("key = { \(item) -> \(item).\(sections.rows.key) },")
        out.line("contentType = { \"\(sections.rows.itemType)\" },")
        out.closeParenAndOpenBody(item)
        let previousItem = context.retainedItem
        context.retainedItem = (sections.rows.itemName, sections.rows.itemType)
        defer { context.retainedItem = previousItem }
        try emit(sections.rows.content, parentAxis: .horizontal, into: &out, context: &context)
        out.close()
        out.close()
        out.close()
        out.close()
        out.close()
    }
}
