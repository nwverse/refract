import RefractIR
import SwiftSyntax

extension Builder {
    /// Builtin modifiers use shared typed values, not mapped component declarations.
    /// A nil result means this is not a builtin and the interop parser may handle it.
    func builtinModifier(_ call: FunctionCallExprSyntax, name: String) -> Modifier? {
        let supported = ["padding", "frame", "background", "cornerRadius", "opacity", "font", "foregroundStyle"]
        guard supported.contains(name) else { return nil }
        guard call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else {
            error("unsupportedModifier", "The modifier `\(name)` does not accept a trailing closure.",
                  "Use the documented scalar modifier arguments.", at: call)
            return nil
        }
        var arguments: [Expression] = []
        var labels: [String?] = call.arguments.map(\.label?.text)
        let diagnosticCount = diagnostics.count
        for argument in call.arguments {
            guard let value = modifierValue(argument.expression) else {
                if diagnostics.count > diagnosticCount { return nil }
                return Modifier(name: name, arguments: [], location: location(of: call))
            }
            arguments.append(value)
        }
        switch name {
        case "padding":
            if arguments.count == 1, labels == [nil] { break }
            if arguments.count == 2 || arguments.count == 4,
               Set(labels).isSubset(of: ["horizontal", "vertical", "value"]),
               labels.contains("horizontal") || labels.contains("vertical") {
                if labels.count == 2, labels[0] == nil, labels[1] == nil,
                   case let .reference(axis) = arguments[0].value,
                   axis == ".horizontal" || axis == ".vertical" {
                    labels[0] = axis == ".horizontal" ? "horizontal" : "vertical"
                    labels[1] = "value"
                    break
                }
                if labels[0] != nil, labels.allSatisfy({ $0 != nil }) { break }
            }
            error("RFVIEW003", "Padding requires one value, one or both axes, or an edge set plus one value.",
                  "Use `.padding(value)` or `.padding(.horizontal, value)` / `.padding(.vertical, value)`.", at: call)
            return nil
        case "frame":
            guard !arguments.isEmpty, labels.allSatisfy({ $0 != nil }),
                  Set(labels.compactMap { $0 }).isSubset(of: ["width", "height", "maxWidth", "maxHeight"]) else {
                error("RFVIEW003", "Frame supports fixed width/height and infinite maxWidth/maxHeight.",
                      "Use labeled dimensions and `.infinity` only for a maximum dimension.", at: call)
                return nil
            }
        case "background", "cornerRadius", "opacity", "font", "foregroundStyle":
            guard arguments.count == 1, labels == [nil] else {
                error("RFVIEW003", "Modifier `\(name)` requires exactly one unlabeled value.",
                      "Use the documented scalar or design-token argument.", at: call)
                return nil
            }
        default:
            return nil
        }
        return Modifier(name: name, arguments: arguments, argumentLabels: labels, location: location(of: call))
    }

    private func modifierValue(_ expression: ExprSyntax) -> Expression? {
        let location = location(of: expression)
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "refractValue" {
            return scalar(expression)?.expression
        }
        if let literal = expression.as(IntegerLiteralExprSyntax.self) {
            return Expression(.numberLiteral(literal.literal.text), location: location)
        }
        if let literal = expression.as(FloatLiteralExprSyntax.self) {
            return Expression(.numberLiteral(literal.literal.text), location: location)
        }
        if expression.as(MemberAccessExprSyntax.self) != nil {
            return Expression(.reference(expression.trimmedDescription), location: location)
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return Expression(.reference(reference.baseName.text), location: location)
        }
        error("RFVIEW003", "The modifier value is not a supported scalar or design-token reference.",
              "Use a numeric literal or a token declared in refract.json.", at: expression)
        return nil
    }
}
