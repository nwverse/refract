import SwiftSyntax

extension Builder {
    func lifecycleMembers(_ node: StructDeclSyntax) -> [RefractLifecycleHooks] {
        guard let body = node.memberBlock.members.first(where: {
            $0.decl.as(VariableDeclSyntax.self)?.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "body"
        })?.decl.as(VariableDeclSyntax.self), let binding = body.bindings.first,
              let accessors = binding.accessorBlock?.accessors, case let .getter(items) = accessors else { return [] }
        return items.flatMap { item -> [RefractLifecycleHooks] in
            guard let expression = item.item.as(ExprSyntax.self) else { return [] }
            return lifecycleHooks(expression)
        }
    }

    private func lifecycleHooks(_ expression: ExprSyntax) -> [RefractLifecycleHooks] {
        if let member = expression.as(MemberAccessExprSyntax.self), member.declName.argumentNames == nil,
           let base = member.base {
            let hook = RefractLifecycleHooks(rawValue: member.declName.baseName.text)
            return lifecycleHooks(base) + (hook.map { [$0] } ?? [])
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base {
            let hook = RefractLifecycleHooks(rawValue: member.declName.baseName.text)
            return lifecycleHooks(base) + (hook.map { [$0] } ?? [])
        }
        return []
    }

    /// Parse and remove only the reserved no-argument lifecycle hooks. The selected content
    /// remains an ordinary SwiftUI view, never a fabricated notification or scheduler view.
    func stripLifecycleHooks(_ expression: ExprSyntax) -> ExprSyntax {
        if let member = expression.as(MemberAccessExprSyntax.self), member.declName.argumentNames == nil,
           RefractLifecycleHooks(rawValue: member.declName.baseName.text) != nil, let base = member.base {
            return stripLifecycleHooks(base)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base,
           RefractLifecycleHooks(rawValue: member.declName.baseName.text) != nil {
            var updated = call
            updated.calledExpression = ExprSyntax(stripLifecycleHooks(base))
            return ExprSyntax(updated)
        }
        return expression
    }
}
