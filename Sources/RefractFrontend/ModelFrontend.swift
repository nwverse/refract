import RefractIR
import SwiftSyntax

extension Builder {
    func collectModels(_ tree: SourceFileSyntax) {
        for statement in tree.statements {
            guard let node = statement.item.as(ProtocolDeclSyntax.self),
                  node.inheritanceClause?.inheritedTypes.contains(where: {
                      $0.type.trimmedDescription == "RefractModel"
                  }) == true else { continue }
            parseModel(node)
        }
    }

    private func parseModel(_ node: ProtocolDeclSyntax) {
        let inherited = node.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
        guard inherited == ["RefractModel"] else {
            error("model.invalid_inheritance", "Model protocol `\(node.name.text)` must inherit only RefractModel.",
                  "Keep the model protocol flat", at: node.name)
            return
        }
        var properties: [ModelProperty] = []
        var actions: [ModelAction] = []
        for member in node.memberBlock.members {
            if let declaration = member.decl.as(VariableDeclSyntax.self) {
                guard let property = modelProperty(declaration) else { return }
                properties.append(property)
            } else if let declaration = member.decl.as(FunctionDeclSyntax.self) {
                guard let action = modelAction(declaration) else { return }
                actions.append(action)
            } else {
                error("model.unsupported_requirement", "This model protocol requirement is not supported.",
                      "Use get-only scalar properties and synchronous Void actions", at: member)
                return
            }
        }
        guard validateUniqueMembers(properties: properties, actions: actions, at: node) else { return }
        models.append(ModelProtocol(name: node.name.text, properties: properties, actions: actions,
                                    location: location(of: node.name)))
    }

    private func validateUniqueMembers(properties: [ModelProperty], actions: [ModelAction],
                                       at node: ProtocolDeclSyntax) -> Bool {
        let propertyNames = Set(properties.map(\.name))
        for action in actions where propertyNames.contains(action.name) {
            error("model.duplicate_member", "Model member `\(action.name)` duplicates another property or action.",
                      "Use uniquely named native properties and actions", at: node.name)
            return false
        }
        var signatures = Set<String>()
        for action in actions {
            let signature = action.name + "(" + action.parameters.map(\.type.rawValue).joined(separator: ",") + ")"
            guard signatures.insert(signature).inserted else {
                diagnostics.append(Diagnostic(code: "model.duplicate_member",
                    message: "Model action `\(signature)` collides with another requirement after Swift external labels are erased on Kotlin.",
                    suggestion: "Use uniquely named native actions instead of overloading only by external argument label",
                    location: action.location ?? location(of: node.name)))
                return false
            }
        }
        return true
    }

    private func modelProperty(_ declaration: VariableDeclSyntax) -> ModelProperty? {
        guard declaration.attributes.isEmpty, declaration.modifiers.isEmpty,
              declaration.bindingSpecifier.tokenKind == .keyword(.var), declaration.bindings.count == 1,
              let binding = declaration.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              scalarType(binding.typeAnnotation?.type.trimmedDescription ?? "") != nil || binding.typeAnnotation?.type.is(ArrayTypeSyntax.self) == true,
              let accessors = binding.accessorBlock?.accessors,
              let collection = modelCollection(binding.typeAnnotation?.type) else {
            error("model.invalid_property", "Model properties must be get-only scalar instance requirements.",
                  "Use a form such as `var title: String { get }`", at: declaration)
            return nil
        }
        guard case let .accessors(list) = accessors, list.count == 1,
              list.first?.accessorSpecifier.tokenKind == .keyword(.get) else {
            error("model.invalid_property", "Model property `\(name)` must be get-only and noncomputed.",
                  "Declare `{ get }` and keep computation in the native implementation", at: accessors)
            return nil
        }
        return ModelProperty(name: name, type: scalarType(binding.typeAnnotation?.type.trimmedDescription ?? "") ?? .string,
                             collection: collection, location: location(of: declaration))
    }

    private func modelCollection(_ annotation: TypeSyntax?) -> ModelCollection?? {
        guard let array = annotation?.as(ArrayTypeSyntax.self) else { return .some(nil) }
        let name = array.element.trimmedDescription
        guard let item = itemTypes.first(where: { $0.name == name }) else {
            // A type that failed Identifiable validation is not a scalar model property.
            // Keep the specific list-identity error rather than manufacturing a scalar fallback.
            if diagnostics.contains(where: { $0.code == "RFLIST001" }) { return nil }
            error("RFLIST001", "Model collection `\(name)` has no stable typed identity and cannot preserve row identity.",
                  "Use Identifiable with a stored String or Int id", at: array)
            return nil
        }
        return .some(ModelCollection(itemType: name, key: item.identity.name, keyType: item.identity.type))
    }

    private func modelAction(_ function: FunctionDeclSyntax) -> ModelAction? {
        guard function.attributes.isEmpty, function.modifiers.isEmpty,
              function.genericParameterClause == nil, function.genericWhereClause == nil,
              function.signature.effectSpecifiers == nil, function.body == nil,
              function.signature.returnClause == nil || function.signature.returnClause?.type.trimmedDescription == "Void" else {
            error("model.invalid_action", "Model action `\(function.name.text)` must be a synchronous, nonthrowing Void requirement.",
                  "Use a nongeneric method with scalar parameters and no async or throws effect", at: function)
            return nil
        }
        var parameters: [ModelParameter] = []
        for parameter in function.signature.parameterClause.parameters {
            guard parameter.ellipsis == nil, parameter.defaultValue == nil,
                  parameter.firstName.tokenKind != .keyword(.inout),
                  parameter.secondName?.tokenKind != .keyword(.inout),
                  let type = scalarType(parameter.type.trimmedDescription) else {
                error("model.invalid_action", "Model action `\(function.name.text)` has an unsupported parameter.",
                      "Use scalar values without defaults, variadics or inout", at: parameter)
                return nil
            }
            let external = parameter.firstName.tokenKind == .wildcard ? nil : parameter.firstName.text
            parameters.append(ModelParameter(externalName: external,
                                              localName: (parameter.secondName ?? parameter.firstName).text, type: type))
        }
        return ModelAction(name: function.name.text, parameters: parameters, location: location(of: function))
    }

    func modelProperty(_ expression: ExprSyntax) -> Expression? {
        // Preserve the scalar-only API used by actions and modifiers. A typed collection is not a string.
        scalarModelProperty(expression)?.expression
    }

    private func scalarModelProperty(_ expression: ExprSyntax) -> TypedExpression? {
        guard let value = modelTypedProperty(expression), value.type != nil else { return nil }
        return value
    }

    func modelTypedProperty(_ expression: ExprSyntax) -> TypedExpression? {
        if let member = expression.as(MemberAccessExprSyntax.self), member.declName.argumentNames == nil,
           let base = member.base?.as(DeclReferenceExprSyntax.self), let item = currentListItem,
           base.baseName.text == item {
            let name = member.declName.baseName.text
            guard let property = currentListItemType?.properties.first(where: { $0.name == name }) else {
                error("RFSEM001", "List item `\(item)` has no declared stored property `\(name)`.",
                      "Use a scalar property declared by the Identifiable item type", at: member)
                return nil
            }
            return TypedExpression(Expression(.reference("\(item).\(property.name)"),
                                             location: location(of: expression)), property.type)
        }
        guard let member = expression.as(MemberAccessExprSyntax.self), member.declName.argumentNames == nil,
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let reference = currentModels.first(where: { $0.propertyName == base.baseName.text }),
              let contract = models.first(where: { $0.name == reference.protocolName }),
              let property = contract.properties.first(where: { $0.name == member.declName.baseName.text }) else { return nil }
        return TypedExpression(Expression(.valueProperty(.model(model: reference.propertyName,
                                                               property: member.declName.baseName.text)),
                                         location: location(of: expression)), property.collection == nil ? property.type : nil)
    }

    func modelAction(_ expression: ExprSyntax) -> StateAction? {
        guard let call = expression.as(FunctionCallExprSyntax.self), call.trailingClosure == nil,
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let reference = currentModels.first(where: { $0.propertyName == base.baseName.text }),
              let contract = models.first(where: { $0.name == reference.protocolName }) else { return nil }
        let name = member.declName.baseName.text
        guard let action = contract.actions.first(where: { $0.name == name }),
              action.parameters.count == call.arguments.count else {
            error("model.invalid_action", "Model action `\(name)` does not match a declared requirement.",
                  "Call a synchronous Void action declared by the model protocol", at: call)
            return nil
        }
        var arguments: [ActionArgument] = []
        for (argument, parameter) in zip(call.arguments, action.parameters) {
            let label = argument.label?.text
            guard label == parameter.externalName,
                  let value = literal(argument.expression, expected: parameter.type) else {
                error("model.invalid_action", "Arguments for model action `\(name)` must match its declaration.",
                      "Preserve Swift argument labels and use scalar literals of the declared types", at: argument)
                return nil
            }
            arguments.append(ActionArgument(label: label, value: value))
        }
        return .modelMethod(model: reference.propertyName, name: name, arguments: arguments)
    }
}
