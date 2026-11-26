import RefractIR
import SwiftSyntax

extension Builder {
    /// A model is get-only in SwiftUI, so a writable search field uses an explicit Binding.
    /// Both closures must refer to the same declared String property and its single-value action.
    func modelTextBinding(_ expression: ExprSyntax) -> Expression? {
        guard let binding = expression.as(FunctionCallExprSyntax.self),
              binding.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Binding",
              binding.arguments.map(\.label?.text) == ["get", "set"],
              binding.trailingClosure == nil, binding.additionalTrailingClosures.isEmpty,
              let get = binding.arguments.first?.expression.as(ClosureExprSyntax.self),
              get.signature == nil, get.statements.count == 1,
              let getter = get.statements.first?.item.as(ExprSyntax.self),
              let read = modelTypedProperty(getter), read.type == .string,
              case let .valueProperty(.model(model, property)) = read.expression.value,
              let set = binding.arguments.last?.expression.as(ClosureExprSyntax.self),
              let valueName = textBindingSetterValue(set),
              let call = set.statements.first?.item.as(ExprSyntax.self)?.as(FunctionCallExprSyntax.self),
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.argumentNames == nil,
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              base.baseName.text == model,
              let reference = currentModels.first(where: { $0.propertyName == model }),
              let contract = models.first(where: { $0.name == reference.protocolName }),
              let action = contract.actions.first(where: { $0.name == member.declName.baseName.text }),
              action.name == "set" + property.prefix(1).uppercased() + property.dropFirst(),
              action.parameters.count == 1, action.parameters[0].type == .string,
              call.arguments.count == 1,
              let argument = call.arguments.first,
              argument.label?.text == action.parameters[0].externalName,
              argument.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == valueName else {
            return nil
        }
        guard action.effect == nil else {
            error("state.invalid_projection",
                  "Editable model text binding setter `\(action.name)` must be synchronous and return Void; `@refractAsync` returns a native attempt result instead.",
                  "Remove `@refractAsync` from `\(action.name)` and keep a synchronous Void setter; use `@refractAsync` only for a separately owned asynchronous attempt",
                  at: expression)
            return nil
        }
        return Expression(.valueProperty(.modelScalarBinding(ModelScalarBinding(
            model: model, property: property, action: action.name))), type: .string,
            location: location(of: expression))
    }

    private func textBindingSetterValue(_ closure: ClosureExprSyntax) -> String? {
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
}
