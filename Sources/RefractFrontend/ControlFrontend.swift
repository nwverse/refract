import RefractIR
import SwiftSyntax

extension Builder {
    func stateControl(_ call: FunctionCallExprSyntax) -> ViewNode? {
        switch call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text {
        case "Toggle": return toggleControl(call)
        case "TextField": return textFieldControl(call)
        default: return nil
        }
    }

    private func toggleControl(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.count == 2, call.trailingClosure == nil,
              call.arguments.first?.label == nil,
              let title = stringLiteral(call.arguments.first!.expression),
              call.arguments.last?.label?.text == "isOn",
              let projection = call.arguments.last?.expression.as(DeclReferenceExprSyntax.self),
              projection.baseName.text.hasPrefix("$"),
              let property = controlBinding(named: String(projection.baseName.text.dropFirst())) else {
            error("state.invalid_projection", "Toggle requires a title and `$property` for a declared scalar state or binding.",
                  "Use `Toggle(\"settings.enabled\", isOn: $isEnabled)` with Bool ownership", at: call)
            return nil
        }
        return .toggle(title: Expression(.stringKey(title), location: location(of: call)),
                       value: Expression(.valueProperty(property), location: location(of: projection)),
                       modifiers: [], location: location(of: call))
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
