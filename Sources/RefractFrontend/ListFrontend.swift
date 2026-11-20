import RefractIR
import SwiftSyntax

extension Builder {
    func collectItemTypes(_ tree: SourceFileSyntax) {
        for statement in tree.statements {
            guard let node = statement.item.as(StructDeclSyntax.self),
                  node.inheritanceClause?.inheritedTypes.contains(where: {
                      $0.type.trimmedDescription == "Identifiable"
                  }) == true else { continue }
            var properties: [ItemProperty] = []
            var identity: ItemProperty?
            var identityDeclaration: VariableDeclSyntax?
            for member in node.memberBlock.members {
                guard let declaration = member.decl.as(VariableDeclSyntax.self),
                      declaration.bindingSpecifier.tokenKind == .keyword(.let),
                      declaration.attributes.isEmpty, declaration.modifiers.isEmpty,
                      declaration.bindings.count == 1,
                      let binding = declaration.bindings.first,
                      binding.initializer == nil, binding.accessorBlock == nil,
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let annotation = binding.typeAnnotation?.type,
                      let property = itemProperty(name: name, annotation: annotation, owner: node.name.text) else {
                    error("RFLIST001", "Identifiable item fields must be stored scalar let properties.",
                          "Use String, Int, Double or Bool stored fields; a ChatMessage may also declare its bounded blocks and UInt64 revision", at: member)
                    if ["ChatMessage", "ChatBlock"].contains(node.name.text) {
                        error("RFMSG001", "A message snapshot has an invalid field, revision, identity or block collection.",
                              "Use the exact ChatMessage/ChatBlock field declarations in docs/message-projection.md", at: member)
                    }
                    return
                }
                properties.append(property)
                if name == "id" {
                    identity = property
                    identityDeclaration = declaration
                }
            }
            guard let identity else {
                error("RFLIST001", "Identifiable item `\(node.name.text)` lacks a stable typed id.",
                      "Declare a stored String or Int id", at: node.name)
                return
            }
            guard identity.type == .string || identity.type == .int else {
                if let declaration = identityDeclaration {
                    error("RFLIST001", "Identifiable item `\(node.name.text)` has an unsupported identity type.",
                          "Use a stored String or Int id", at: declaration)
                    if ["ChatMessage", "ChatBlock"].contains(node.name.text) {
                        error("RFMSG001", "Message and block identities must be independent stored String ids.",
                              "Declare `let id: String` on both snapshot types", at: declaration)
                    }
                }
                return
            }
            itemTypes.append(ItemType(name: node.name.text, identity: identity, properties: properties,
                                      location: location(of: node.name),
                                      messageProjection: node.name.text == "ChatMessage" || node.name.text == "ChatBlock"))
        }
    }

    private func itemProperty(name: String, annotation: TypeSyntax, owner: String) -> ItemProperty? {
        let typeName = annotation.trimmedDescription
        if owner == "ChatMessage", typeName == "[ChatBlock]", name == "blocks" {
            return ItemProperty(name: name, type: .string,
                                collection: ItemCollection(itemType: "ChatBlock", owner: owner, property: name),
                                declaredType: typeName)
        }
        if owner == "ChatMessage", typeName == "UInt64", name == "revision" {
            return ItemProperty(name: name, type: .revision, declaredType: typeName)
        }
        if let arrayType = annotation.as(ArrayTypeSyntax.self),
           let elementName = arrayType.element.as(IdentifierTypeSyntax.self)?.name.text,
           name != "id", itemTypes.contains(where: { $0.name == elementName }) {
            return ItemProperty(name: name, type: .string,
                                collection: ItemCollection(itemType: elementName, owner: owner, property: name),
                                declaredType: typeName)
        }
        let enumName = enums.contains(where: { $0.name == typeName && $0.payloadTypes.isEmpty }) ? typeName : nil
        guard let type = scalarType(typeName) ?? (enumName == nil ? nil : .string) else { return nil }
        return ItemProperty(name: name, type: type, declaredType: typeName, enumName: enumName)
    }

    func dynamicList(_ call: FunctionCallExprSyntax) -> ViewNode? {
        if currentListItem != nil {
            guard currentListItemType?.name == "ChatMessage" else {
                error("RFLIST003", "A dynamic List cannot be nested inside another dynamic row.",
                      "Expose a separate screen or a flat model collection with stable identity", at: call)
                return nil
            }
            return messageBlocks(call)
        }
        if call.arguments.count == 2, call.arguments[call.arguments.index(after: call.arguments.startIndex)].label?.text == "id" {
            let argument = call.arguments[call.arguments.index(after: call.arguments.startIndex)]
            error("RFLIST002", "An explicit List identity must use the item's stable stored id.",
                  "Use `List(model.items)` with a stored String or Int id; never use `\\.self` or an array index",
                  at: argument.expression)
            return nil
        }
        guard let collectionExpression = call.arguments.first?.expression,
              let (collection, projection) = projectedCollection(collectionExpression),
              let member = sourceCollectionMember(collectionExpression),
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let reference = currentModels.first(where: { $0.propertyName == base.baseName.text }),
              let model = models.first(where: { $0.name == reference.protocolName }),
              let property = model.properties.first(where: { $0.name == member.declName.baseName.text }),
              let descriptor = property.collection,
              let item = itemTypes.first(where: { $0.name == descriptor.itemType }),
              let closure = call.trailingClosure,
              let itemName = closureItemName(closure) else {
            error("RFLIST001", "A dynamic List needs a declared identifiable model collection and one item view.",
                  "Use a RefractModel collection of Identifiable items with a stable String or Int id", at: call)
            return nil
        }
        guard call.arguments.count == 1 else {
            error("RFLIST003", "Dynamic rows must be directly owned by List.",
                  "Use List(model.items) or ForEach(model.items) inside List", at: call)
            return nil
        }
        let previousItem = currentListItem
        let previousType = currentListItemType
        currentListItem = itemName
        currentListItemType = item
        defer {
            currentListItem = previousItem
            currentListItemType = previousType
        }
        let row = children(of: closure)
        guard let row else { return nil }
        guard row.count == 1, let content = row.first else {
            error("RFLIST003", "A dynamic List row must contain exactly one view.",
                  "Wrap multiple row views in one supported container", at: closure)
            return nil
        }
        if descriptor.itemType == "ChatMessage" {
            guard isMessageCollection(collectionExpression) else { return nil }
            pendingMessageSources.append((collection, content, currentViewName ?? "", reference.protocolName))
            pendingMessageOwners[currentViewName ?? ""] = Screen(name: currentViewName ?? "",
                parameters: parameters, states: currentStates, body: content)
            return nil
        }
        let items = ListItems(collection: collection, itemName: itemName, itemType: descriptor.itemType,
                              key: descriptor.key, keyType: descriptor.keyType, content: content,
                              contentType: rowContentType(content), projection: projection,
                              modelType: reference.protocolName, location: location(of: call))
        return .list(children: [.forEach(items, location: location(of: call))], modifiers: [], location: location(of: call))
    }

    func forEachCall(_ expression: ExprSyntax) -> FunctionCallExprSyntax? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "ForEach" else { return nil }
        return call
    }

    func isMessageCollection(_ expression: ExprSyntax?) -> Bool {
        guard let expression,
              let member = expression.as(MemberAccessExprSyntax.self),
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let reference = currentModels.first(where: { $0.propertyName == base.baseName.text }),
              let model = models.first(where: { $0.name == reference.protocolName }) else { return false }
        return model.properties.first(where: { $0.name == member.declName.baseName.text })?.collection?.itemType == "ChatMessage"
    }

    func forEachList(_ call: FunctionCallExprSyntax, owner: FunctionCallExprSyntax) -> ViewNode? {
        guard currentListItem == nil else {
            error("RFLIST003", "ForEach cannot be nested inside another dynamic row.",
                  "Use one flat ForEach(model.items) directly inside List", at: call)
            return nil
        }
        guard let collectionExpression = call.arguments.first?.expression,
              call.arguments.first?.label == nil,
              (call.arguments.count == 1 ||
               (call.arguments.count == 2 && call.arguments.last?.label?.text == "id")),
              let closure = call.trailingClosure, call.additionalTrailingClosures.isEmpty,
              let itemName = closureItemName(closure) else {
            error("RFLIST003", "ForEach requires one model collection, an optional stored id, and one named item closure.",
                  "Use List { ForEach(model.items) { item in ... } } or the explicit id: \\.id form", at: call)
            return nil
        }
        guard let descriptor = modelCollectionDescriptor(collectionExpression) else {
            if collectionExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "indices" {
                error("RFLIST002", "An array index is not stable list identity.",
                      "Use ForEach(model.items) or ForEach(model.items, id: \\.id) with a stored String or Int id",
                      at: collectionExpression)
            } else if collectionExpression.as(MemberAccessExprSyntax.self) == nil {
                error("RFLIST003", "This ForEach would eagerly render an unsupported or untyped collection.",
                      "Use List { ForEach(model.items) { item in ... } } with an identifiable model collection",
                      at: collectionExpression)
            } else {
                error("RFLIST001", "ForEach needs a declared identifiable model collection with stable typed identity.",
                      "Use a RefractModel collection of Identifiable items with a stored String or Int id",
                      at: collectionExpression)
            }
            return nil
        }
        let (collection, item, modelType) = descriptor
        let projection: CollectionProjection?
        if let projected = projectedCollection(collectionExpression), projected.1 != nil {
            projection = projected.1
        } else if collectionExpression.as(MemberAccessExprSyntax.self) != nil {
            projection = nil
        } else {
            return nil
        }
        if call.arguments.count == 2, let identity = call.arguments.last?.expression,
           !isDeclaredStoredID(identity, item: item) {
            error("RFLIST002", "ForEach identity must be the item's declared stable stored id.",
                  "Use ForEach(model.items) or ForEach(model.items, id: \\.id); never use \\.self, another property, or an array index",
                  at: identity)
            return nil
        }
        let previousItem = currentListItem
        let previousType = currentListItemType
        currentListItem = itemName
        currentListItemType = item
        defer {
            currentListItem = previousItem
            currentListItemType = previousType
        }
        let row = children(of: closure)
        guard let row else { return nil }
        guard row.count == 1, let content = row.first else {
            error("RFLIST003", "A ForEach row must contain exactly one view.",
                  "Wrap multiple row views in one supported container", at: closure)
            return nil
        }
        let items = ListItems(collection: collection, itemName: itemName, itemType: item.name,
                              key: item.identity.name, keyType: item.identity.type, content: content,
                              contentType: rowContentType(content), projection: projection, modelType: modelType,
                              location: location(of: call))
        return .list(children: [.forEach(items, location: location(of: call))], modifiers: [],
                     location: location(of: owner))
    }

    private func isDeclaredStoredID(_ expression: ExprSyntax, item: ItemType) -> Bool {
        guard let keyPath = expression.as(KeyPathExprSyntax.self), keyPath.root == nil,
              keyPath.components.count == 1, let component = keyPath.components.first,
              case let .property(property) = component.component,
              property.genericArgumentClause == nil else { return false }
        return property.declName.baseName.text == item.identity.name
    }

    func modelCollectionDescriptor(_ expression: ExprSyntax) -> (Expression, ItemType, String)? {
        guard let member = sourceCollectionMember(expression), member.declName.argumentNames == nil,
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let reference = currentModels.first(where: { $0.propertyName == base.baseName.text }),
              let model = models.first(where: { $0.name == reference.protocolName }),
              let property = model.properties.first(where: { $0.name == member.declName.baseName.text }),
              let descriptor = property.collection,
              let item = itemTypes.first(where: { $0.name == descriptor.itemType }) else { return nil }
        return (Expression(.valueProperty(.model(model: reference.propertyName,
                                                 property: member.declName.baseName.text)),
                           location: location(of: expression)), item, reference.protocolName)
    }

    private func modelCollectionProperty(_ expression: ExprSyntax) -> Expression? {
        guard let member = sourceCollectionMember(expression), member.declName.argumentNames == nil,
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let reference = currentModels.first(where: { $0.propertyName == base.baseName.text }),
              let model = models.first(where: { $0.name == reference.protocolName }),
              let property = model.properties.first(where: { $0.name == member.declName.baseName.text }),
              property.collection != nil else { return nil }
        return Expression(.valueProperty(.model(model: reference.propertyName,
                                                property: member.declName.baseName.text)),
                          location: location(of: expression))
    }

    func validateCollectionProjections() {
        func visit(_ node: ViewNode) {
            if case let .forEach(items, _) = node, let projection = items.projection,
               let modelName = items.modelType,
               let index = models.firstIndex(where: { $0.name == modelName }),
               !models[index].projectedCollections.contains(projection.name) {
                models[index].projectedCollections.append(projection.name)
            }
            for child in node.children { visit(child) }
        }
        for screen in screens { visit(screen.body) }
    }

    func validateRowContentTypes(_ module: Module) {
        for screen in module.screens {
            func visit(_ node: ViewNode, directDynamicRow: Bool = false) {
                if case let .child(child, location) = node, child.contentType != nil, !directDynamicRow {
                    diagnostics.append(Diagnostic(code: "RFNATIVE004",
                        message: "A row content type requires a generated child directly owned by a dynamic List.",
                        suggestion: "Apply `.contentType(\"setting\")` only to the generated child row inside List(model.items) or List { ForEach(model.items) }",
                        location: location))
                }
                for child in node.children {
                    if case let .forEach(items, _) = child {
                        visit(items.content, directDynamicRow: true)
                    } else {
                        visit(child)
                    }
                }
            }
            visit(screen.body)
        }
    }

    private func rowContentType(_ content: ViewNode) -> String? {
        if case let .child(child, _) = content { return child.contentType }
        return nil
    }

    func closureItemName(_ closure: ClosureExprSyntax) -> String? {
        guard let parameters = closure.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self),
              parameters.count == 1 else { return nil }
        return parameters.first?.name.text
    }
}
