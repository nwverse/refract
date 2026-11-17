import RefractIR
import SwiftSyntax

extension Builder {
    func stateControl(_ call: FunctionCallExprSyntax) -> ViewNode? {
        switch call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text {
        case "Toggle": return toggleControl(call)
        case "TextField": return textFieldControl(call)
        case "SecureField": return secureFieldControl(call)
        default: return nil
        }
    }

    /// `.secureReveal($isRevealed)` attaches a projected Bool reveal flag to a `SecureField`.
    /// v0 requires the projection to refer to a declared Bool @State or @Binding; literals,
    /// expressions and `.constant(true)` are rejected so reveal ownership stays typed and visible.
    func secureReveal(_ call: FunctionCallExprSyntax, on node: ViewNode) -> ViewNode? {
        guard call.arguments.count == 1, call.trailingClosure == nil,
              call.arguments.first?.label == nil,
              let projection = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
              projection.baseName.text.hasPrefix("$"),
              let property = controlBinding(named: String(projection.baseName.text.dropFirst())) else {
            error("RFSECURE001",
                  "`.secureReveal` takes exactly one projected Bool @State or @Binding (`$isRevealed`).",
                  "Declare `@State private var isRevealed: Bool = false` and pass `.secureReveal($isRevealed)`",
                  at: call)
            return nil
        }
        guard case let .secureInput(placeholder, value, reveal, modifiers, nodeLocation) = node, reveal == nil else {
            error("RFSECURE001",
                  "`.secureReveal` applies once, directly to a `SecureField`.",
                  "Place `.secureReveal($isRevealed)` on the SecureField before layout modifiers", at: call)
            return nil
        }
        let revealExpression = Expression(.valueProperty(property), type: .bool, location: location(of: projection))
        return .secureInput(placeholder: placeholder, value: value, reveal: revealExpression,
                            modifiers: modifiers, location: nodeLocation)
    }

    func labelsHidden(_ call: FunctionCallExprSyntax, on node: ViewNode) -> ViewNode? {
        guard call.arguments.isEmpty, call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else {
            error("RFVIEW003", "`labelsHidden()` takes no arguments or child closure.",
                  "Apply `.labelsHidden()` directly to a supported Toggle", at: call)
            return nil
        }
        guard case let .toggle(title, value, modifiers, nativeModifiers, hidden, location) = node, !hidden else {
            error("RFVIEW003", "`labelsHidden()` applies once to a supported Toggle.",
                  "Put `.labelsHidden()` directly after the Toggle or its measurement modifiers", at: call)
            return nil
        }
        return .toggle(title: title, value: value, modifiers: modifiers, nativeModifiers: nativeModifiers,
                       labelsHidden: true, location: location)
    }

    private func toggleControl(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.count == 2, call.trailingClosure == nil,
              call.arguments.first?.label == nil,
              call.arguments.last?.label?.text == "isOn",
              let titleExpression = controlToggleTitle(call.arguments.first!.expression),
              let value = controlToggleValue(call.arguments.last!.expression, title: titleExpression) else {
            error("state.invalid_projection",
                  "Toggle requires a local/parent Bool binding or a typed list-item Bool binding backed by a model action.",
                  "Use `isOn: $isEnabled`, or a matching item getter and `model.action(item.id, value: $0)` setter", at: call)
            return nil
        }
        return .toggle(title: titleExpression, value: value, modifiers: [], location: location(of: call))
    }

    private func controlToggleTitle(_ expression: ExprSyntax) -> Expression? {
        if let key = stringLiteral(expression) {
            return Expression(.stringKey(key), location: location(of: expression))
        }
        var parser = LocalizationFrontend(file: file, converter: converter, scalar: scalar,
                                          typedScalar: modelTypedProperty,
                                          stateText: { _ in nil }, enumInputNames: [])
        defer { diagnostics.append(contentsOf: parser.diagnostics) }
        guard let literal = expression.as(StringLiteralExprSyntax.self),
              let text = parser.localized(ExprSyntax(literal)),
              case let .localizedText(localized) = text.value else { return nil }
        return Expression(.localizedText(localized), type: .string, location: location(of: expression))
    }

    private func controlToggleValue(_ expression: ExprSyntax, title: Expression) -> Expression? {
        if let projection = expression.as(DeclReferenceExprSyntax.self), projection.baseName.text.hasPrefix("$"),
           let property = controlBinding(named: String(projection.baseName.text.dropFirst())) {
            return Expression(.valueProperty(property), type: .bool, location: location(of: projection))
        }
        guard let binding = expression.as(FunctionCallExprSyntax.self),
              binding.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Binding",
              binding.arguments.map(\.label?.text) == ["get", "set"], binding.trailingClosure == nil,
              let get = binding.arguments.first?.expression.as(ClosureExprSyntax.self),
              get.signature == nil, get.statements.count == 1,
              let getter = get.statements.first?.item.as(ExprSyntax.self),
              let property = modelTypedProperty(getter), property.type == .bool,
              case let .reference(read) = property.expression.value,
              let item = currentListItem, read.hasPrefix(item + "."),
              currentListItemType?.properties.contains(where: { $0.type == .bool && read == item + "." + $0.name }) == true,
              let set = binding.arguments.last?.expression.as(ClosureExprSyntax.self),
              let valueName = toggleSetterValue(set),
              let item = currentListItem, item == titleItem(title),
              let action = toggleSetterAction(set, valueName: valueName, item: item) else { return nil }
        return Expression(.valueProperty(.itemBinding(ItemBinding(
            model: action.model, item: item, property: String(read.dropFirst(item.count + 1)),
            key: action.key, action: action.name))), type: .bool, location: location(of: expression))
    }

    private func titleItem(_ title: Expression) -> String? {
        guard case let .localizedText(text) = title.value, !text.arguments.isEmpty,
              let item = currentListItem else { return nil }
        for argument in text.arguments {
            guard argument.type != nil, case let .reference(reference) = argument.value,
                  let property = reference.split(separator: ".").last,
                  currentListItemType?.properties.contains(where: {
                      $0.name == property && $0.type == argument.type
                  }) == true,
                  reference == "\(item).\(property)" else { return nil }
        }
        return item
    }

    private func toggleSetterValue(_ closure: ClosureExprSyntax) -> String? {
        guard closure.statements.count == 1 else { return nil }
        guard let signature = closure.signature, let parameters = signature.parameterClause else { return "$0" }
        switch parameters {
        case let .parameterClause(clause):
            guard clause.parameters.count == 1, clause.parameters.first?.secondName == nil else { return nil }
            return clause.parameters.first?.firstName.text
        case let .simpleInput(input):
            guard input.count == 1 else { return nil }
            return input.first?.name.text
        }
    }

    private func toggleSetterAction(_ closure: ClosureExprSyntax, valueName: String,
                                    item: String) -> (model: String, key: String, name: String)? {
        guard let call = closure.statements.first?.item.as(ExprSyntax.self)?.as(FunctionCallExprSyntax.self),
              call.trailingClosure == nil,
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.argumentNames == nil,
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let reference = currentModels.first(where: { $0.propertyName == base.baseName.text }),
              let contract = models.first(where: { $0.name == reference.protocolName }),
              let action = contract.actions.first(where: { $0.name == member.declName.baseName.text }),
              action.parameters.count == 2, action.parameters[0].type == currentListItemType?.identity.type,
              action.parameters[1].type == .bool else { return nil }
        let arguments = Array(call.arguments)
        guard arguments.count == 2,
              arguments[0].label?.text == action.parameters[0].externalName,
              arguments[1].label?.text == action.parameters[1].externalName,
              let identity = currentListItemType?.identity,
              modelTypedProperty(arguments[0].expression)?.expression.value
                == .reference(item + "." + identity.name),
              arguments[1].expression.as(DeclReferenceExprSyntax.self)?.baseName.text == valueName else { return nil }
        return (reference.propertyName, identity.name, action.name)
    }

    private func textFieldControl(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.count == 2, call.trailingClosure == nil,
              let titleArgument = call.arguments.first, titleArgument.label == nil,
              let key = stringLiteral(titleArgument.expression), LocalizationKey.isCanonical(key),
              call.arguments.last?.label?.text == "text",
              let projection = call.arguments.last?.expression.as(DeclReferenceExprSyntax.self),
              projection.baseName.text.hasPrefix("$"),
              let property = controlTextBinding(named: String(projection.baseName.text.dropFirst())) else {
            error("state.invalid_projection",
                  "TextField requires a localized title and `text: $property` for a declared String state or binding.",
                  "Use `TextField(\"settings.name\", text: $name)` with String ownership", at: call)
            return nil
        }
        let placeholder = Expression(.localizedText(LocalizedText(key: key)), type: .string,
                                    location: location(of: titleArgument.expression))
        return .textInput(placeholder: placeholder,
                          value: Expression(.valueProperty(property), location: location(of: projection)),
                          modifiers: [], location: location(of: call))
    }

    private func secureFieldControl(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.count == 2, call.trailingClosure == nil,
              let titleArgument = call.arguments.first, titleArgument.label == nil,
              let key = stringLiteral(titleArgument.expression), LocalizationKey.isCanonical(key),
              call.arguments.last?.label?.text == "text",
              let projection = call.arguments.last?.expression.as(DeclReferenceExprSyntax.self),
              projection.baseName.text.hasPrefix("$"),
              let property = controlTextBinding(named: String(projection.baseName.text.dropFirst())) else {
            error("RFSECURE002",
                  "SecureField requires a localized title key and `text: $property` for a declared String state or binding.",
                  "Use `SecureField(\"settings.password\", text: $password)` with String ownership", at: call)
            return nil
        }
        let placeholder = Expression(.localizedText(LocalizedText(key: key)), type: .string,
                                    location: location(of: titleArgument.expression))
        return .secureInput(placeholder: placeholder,
                            value: Expression(.valueProperty(property), location: location(of: projection)),
                            reveal: nil, modifiers: [], location: location(of: call))
    }

    private func controlTextBinding(named name: String) -> ValueProperty? {
        for declaration in currentStates {
            switch declaration {
            case let .state(declared, .string, _, _) where declared == name: return .state(name)
            case let .binding(declared, .string, _) where declared == name: return .binding(name)
            default: continue
            }
        }
        return nil
    }

    private func controlBinding(named name: String) -> ValueProperty? {
        for declaration in currentStates {
            switch declaration {
            case let .state(declared, .bool, _, _) where declared == name: return .state(name)
            case let .binding(declared, .bool, _) where declared == name: return .binding(name)
            default: continue
            }
        }
        return nil
    }
}
