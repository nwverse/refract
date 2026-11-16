import RefractIR

/// Atomic resource resolution for CLI and golden generation, before any native output is emitted.
public enum LocalizationResourceValidator {
    public static func validate(module: Module, mapping: Mapping) throws {
        for expression in localizedExpressions(in: module) {
            guard case let .localizedText(text) = expression.value else { continue }
            _ = try mapping.stringCatalog(text, platform: .android, location: expression.location)
            _ = try mapping.stringCatalog(text, platform: .harmonyOS, location: expression.location)
        }
    }

    private static func localizedExpressions(in module: Module) -> [Expression] {
        func visit(_ node: ViewNode) -> [Expression] {
            switch node {
            case let .text(expression, modifiers, _):
                return [expression] + modifiers.flatMap(\.arguments)
            case let .stack(_, children, modifiers, _):
                return children.flatMap(visit) + modifiers.flatMap(\.arguments)
            case let .button(label, action, modifiers, _):
                return visit(label) + (action.map { [$0] } ?? []) + modifiers.flatMap(\.arguments)
            case let .native(component, _):
                return component.arguments.map(\.expression)
            case let .platformView(alternatives, _):
                return (alternatives.android + alternatives.harmonyOS).flatMap(visit)
            case let .conditional(branches, _):
                return branches.flatMap { branch in
                    (branch.condition.map { [$0] } ?? []) + branch.children.flatMap(visit)
                }
            }
        }
        func expressions(in value: Expression) -> [Expression] {
            if case let .localizedText(text) = value.value {
                return [value] + text.arguments.flatMap(expressions)
            }
            if case let .platformValue(alternatives) = value.value {
                return [alternatives.android, alternatives.harmonyOS].flatMap(expressions)
            }
            return []
        }
        return module.screens.flatMap { visit($0.body) }.flatMap(expressions)
    }
}
