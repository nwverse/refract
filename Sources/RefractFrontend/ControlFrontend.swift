import RefractIR
import SwiftSyntax

extension Builder {
    func stateControl(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Toggle" else { return nil }
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
