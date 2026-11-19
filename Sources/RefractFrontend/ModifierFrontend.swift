import RefractIR
import RefractMapping
import SwiftSyntax

extension Builder {
    /// Builtin modifiers use shared typed values, not mapped component declarations.
    /// A nil result means this is not a builtin and the interop parser may handle it.
    func builtinModifier(_ call: FunctionCallExprSyntax, name: String) -> Modifier? {
        let supported = ["padding", "frame", "background", "cornerRadius", "opacity", "font", "foregroundStyle", "layoutPriority"]
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
            if arguments.count == 2, labels == [nil, nil],
               case let .reference(axis) = arguments[0].value,
               axis == ".horizontal" || axis == ".vertical" {
                labels[0] = axis == ".horizontal" ? "horizontal" : "vertical"
                labels[1] = "value"
                break
            }
            if arguments.count == 1, labels == [nil] { break }
            if arguments.count == 2 || arguments.count == 4,
               labels.allSatisfy({ $0 == "horizontal" || $0 == "vertical" || $0 == "value" }),
               labels.contains(where: { $0 == "horizontal" || $0 == "vertical" }) {
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
        case "background", "cornerRadius", "opacity", "font", "foregroundStyle", "layoutPriority":
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
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "custom",
           (member.base == nil || member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "Font") {
            let labels = call.arguments.map(\.label?.text)
            let arguments = Array(call.arguments)
            guard labels == [nil, "size", "relativeTo"],
                  let name = stringLiteral(arguments[0].expression),
                  AssetCatalog.isResourceName(name),
                  let size = arguments[1].expression.as(IntegerLiteralExprSyntax.self),
                  let points = Int(size.literal.text), (1...256).contains(points),
                  let textStyle = arguments[2].expression.as(MemberAccessExprSyntax.self),
                  textStyle.base == nil, textStyle.declName.baseName.text == "body",
                  call.trailingClosure == nil else {
                error("RFVIEW003", "Custom fonts require a declared name, bounded point size and body-relative scaling.",
                      "Use Font.custom(\"font_name\", size: 16, relativeTo: .body)", at: expression)
                return nil
            }
            return Expression(.fontAsset(name: name, size: String(points)), location: location)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "refractInteractionColor" {
            guard call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
                  call.arguments.count == 4,
                  call.arguments.map(\.label?.text) == [nil, "enabled", "pressed", "focused"],
                  let tokenExpression = call.arguments.first?.expression.as(MemberAccessExprSyntax.self),
                  tokenExpression.trimmedDescription.contains(".") else {
                error("interactionToken", "An interaction color needs one color token and three explicit Boolean values.",
                      "Use `refractInteractionColor(DesignColors.action, enabled: enabled, pressed: pressed, focused: focused)`.", at: call)
                return nil
            }
            var values: [String: Expression] = [:]
            for argument in call.arguments.dropFirst() {
                guard let label = argument.label?.text, let value = scalar(argument.expression),
                      value.type == .bool else {
                    error("interactionToken", "Interaction enabled, pressed and focused inputs must be declared Boolean values.",
                          "Use app-provided Bool state; never substitute a detached InteractionSource or another state.", at: argument)
                    return nil
                }
                values[label] = value.expression
            }
            guard let enabled = values["enabled"], let pressed = values["pressed"], let focused = values["focused"] else {
                return nil
            }
            let token = tokenExpression.trimmedDescription
            return Expression(.interactionColor(InteractionColorValue(token: token, enabled: enabled,
                pressed: pressed, focused: focused)), location: location)
        }
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
