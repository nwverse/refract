import RefractIR
import SwiftSyntax

extension Builder {
    /// Recognizes `ForEach(model.sections) { section in Section(section.title) { ... } }`.
    /// Returns nil silently when the outer ForEach is not a section wrapper so that the
    /// ordinary dynamic-list path handles it. Once the Section shape is recognized the
    /// inner contract is strict: any deviation is an RFLIST004 diagnostic.
    func horizontalSections(_ call: FunctionCallExprSyntax) -> ViewNode? {
        // Recognition gate (no diagnostics): outer ForEach over a model collection whose
        // single child is a Section(...) call.
        guard call.arguments.count == 1, call.arguments.first?.label == nil,
              let collectionExpression = call.arguments.first?.expression,
              let descriptor = modelCollectionDescriptor(collectionExpression),
              let closure = call.trailingClosure, call.additionalTrailingClosures.isEmpty,
              let sectionName = closureItemName(closure),
              closure.statements.count == 1, let statement = closure.statements.first,
              let sectionCall = statement.item.as(FunctionCallExprSyntax.self),
              sectionCall.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Section"
        else { return nil }

        // From here on the shape is committed: validate the full inner contract.
        let sectionType = itemTypes.first(where: { $0.name == descriptor.1.name })
        guard let sectionType,
              sectionCall.arguments.count == 1, sectionCall.arguments.first?.label == nil,
              sectionCall.additionalTrailingClosures.isEmpty,
              let titleExpression = sectionCall.arguments.first?.expression,
              let titleReference = titleExpression.as(MemberAccessExprSyntax.self),
              titleReference.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == sectionName,
              let titleProperty = sectionType.properties.first(where: {
                  $0.name == titleReference.declName.baseName.text && $0.type == .string
              }),
              let bodyClosure = sectionCall.trailingClosure else {
            error("RFLIST004", "Horizontal sections require an identified section collection and a direct Section(section.title) header.",
                  "Use List { ForEach(model.sections) { section in Section(section.title) { ... } } }", at: sectionCall)
            return nil
        }
        guard bodyClosure.statements.count == 1, let rowStatement = bodyClosure.statements.first,
              let scrollCall = rowStatement.item.as(FunctionCallExprSyntax.self),
              scrollCall.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "ScrollView",
              scrollCall.arguments.count == 1, scrollCall.arguments.first?.label == nil,
              let axis = scrollCall.arguments.first?.expression.as(MemberAccessExprSyntax.self),
              axis.base == nil, axis.declName.baseName.text == "horizontal",
              scrollCall.additionalTrailingClosures.isEmpty,
              let scrollClosure = scrollCall.trailingClosure,
              scrollClosure.statements.count == 1, let stackStatement = scrollClosure.statements.first,
              let stackCall = stackStatement.item.as(FunctionCallExprSyntax.self),
              stackCall.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "LazyHStack",
              stackCall.arguments.isEmpty, stackCall.additionalTrailingClosures.isEmpty,
              let stackClosure = stackCall.trailingClosure,
              stackClosure.statements.count == 1, let forEachStatement = stackClosure.statements.first,
              let forEach = forEachStatement.item.as(ExprSyntax.self).flatMap(forEachCall),
              forEach.arguments.count == 1, forEach.arguments.first?.label == nil,
              let collection = forEach.arguments.first?.expression.as(MemberAccessExprSyntax.self),
              collection.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == sectionName,
              let itemsProperty = sectionType.properties.first(where: {
                  $0.name == collection.declName.baseName.text && $0.collection != nil
              }),
              let itemsCollection = itemsProperty.collection,
              itemsCollection.owner == sectionType.name,
              let rowClosure = forEach.trailingClosure, forEach.additionalTrailingClosures.isEmpty,
              let itemName = closureItemName(rowClosure), itemName != sectionName,
              let itemType = itemTypes.first(where: { $0.name == itemsCollection.itemType }) else {
            error("RFLIST004", "A horizontal section needs one ScrollView(.horizontal) with one LazyHStack and one identified ForEach over the section's item collection.",
                  "Use Section(section.title) { ScrollView(.horizontal) { LazyHStack { ForEach(section.items) { item in ... } } } }", at: bodyClosure)
            return nil
        }
        let previousItem = currentListItem
        let previousType = currentListItemType
        currentListItem = itemName
        currentListItemType = itemType
        defer {
            currentListItem = previousItem
            currentListItemType = previousType
        }
        guard let rows = children(of: rowClosure), rows.count == 1, let content = rows.first else {
            error("RFLIST004", "A horizontal row needs exactly one direct supported view.",
                  "Use one Text or supported bounded view per horizontal item", at: rowClosure)
            return nil
        }
        let rowsIR = HorizontalItemCollection(property: itemsProperty.name, itemName: itemName,
            itemType: itemType.name, key: itemType.identity.name, keyType: itemType.identity.type,
            content: content, location: location(of: forEach))
        return .horizontalSections(HorizontalSectionCollection(
            collection: descriptor.0, modelType: descriptor.2, sectionName: sectionName,
            sectionType: sectionType.name, sectionKey: sectionType.identity.name,
            sectionKeyType: sectionType.identity.type, titleProperty: titleProperty.name,
            rows: rowsIR, location: location(of: call)), location: location(of: call))
    }
}
