import RefractIR
import SwiftSyntax

extension Builder {
    func collectItemTypes(_ tree: SourceFileSyntax) {
        for statement in tree.statements {
            guard let node = statement.item.as(StructDeclSyntax.self),
                  node.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) == ["Identifiable"] else { continue }
            var properties: [ItemProperty] = []
            var identity: ItemProperty?
            for member in node.memberBlock.members {
                guard let declaration = member.decl.as(VariableDeclSyntax.self),
                      declaration.bindingSpecifier.tokenKind == .keyword(.let),
                      declaration.attributes.isEmpty, declaration.bindings.count == 1,
                      let binding = declaration.bindings.first,
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let type = scalarType(binding.typeAnnotation?.type.trimmedDescription ?? "") else {
                    error("RFLIST001", "Identifiable item fields must be stored scalar let properties.",
                          "Use String, Int, Double or Bool stored fields", at: member)
                    return
                }
                let property = ItemProperty(name: name, type: type)
                properties.append(property)
                if name == "id" { identity = property }
            }
            guard let identity else {
                error("RFLIST001", "Identifiable item `\(node.name.text)` lacks a stable typed id.",
                      "Declare a stored String or Int id", at: node.name)
                return
            }
            itemTypes.append(ItemType(name: node.name.text, identity: identity, properties: properties,
                                      location: location(of: node.name)))
        }
    }

    func dynamicList(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard let collectionExpression = call.arguments.first?.expression,
              let collection = modelProperty(collectionExpression),
              let member = collectionExpression.as(MemberAccessExprSyntax.self),
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let reference = currentModels.first(where: { $0.propertyName == base.baseName.text }),
              let model = models.first(where: { $0.name == reference.protocolName }),
              let property = model.properties.first(where: { $0.name == member.declName.baseName.text }),
              let descriptor = property.collection,
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
        currentListItem = itemName
        defer { currentListItem = nil }
        let content = children(of: closure)?.first
        guard let content else {
            error("RFLIST001", "A dynamic List item requires one supported view.", at: closure)
            return nil
        }
        let items = ListItems(collection: collection, itemName: itemName, itemType: descriptor.itemType,
                              key: descriptor.key, keyType: descriptor.keyType, content: content,
                              location: location(of: call))
        return .list(children: [.forEach(items, location: location(of: call))], modifiers: [], location: location(of: call))
    }

    private func closureItemName(_ closure: ClosureExprSyntax) -> String? {
        guard let parameters = closure.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self),
              parameters.count == 1 else { return nil }
        return parameters.first?.name.text
    }
}
