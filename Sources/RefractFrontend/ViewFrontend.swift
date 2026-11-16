import RefractIR
import SwiftSyntax

/// View syntax additions. Unsupported shapes are diagnosed rather than lowered by spelling alone.
extension Builder {
    private static let extendedViews: Set<String> = ["VStack", "HStack", "ZStack", "ScrollView", "List", "Section", "Image", "Label", "Divider", "Spacer"]

    func extendedViewHandles(name: String) -> Bool {
        Self.extendedViews.contains(name)
    }

    func extendedView(_ call: FunctionCallExprSyntax) -> ViewNode? {
        let name = call.calledExpression.trimmedDescription
        guard Self.extendedViews.contains(name) else { return nil }
        switch name {
        case "VStack", "HStack", "ZStack": return stack(call)
        case "ScrollView": return scroll(call)
        case "List":
            if call.arguments.isEmpty { return staticList(call) }
            return dynamicList(call)
        case "Section": return section(call)
        case "Image": return image(call)
        case "Label": return label(call)
        case "Divider": return leaf(call, .divider(modifiers: [], location: location(of: call)))
        case "Spacer": return leaf(call, .spacer(location: location(of: call)))
        default: return nil
        }
    }

    private func stack(_ call: FunctionCallExprSyntax) -> ViewNode? {
        let name = call.calledExpression.trimmedDescription
        guard let children = children(of: call.trailingClosure) else { return nil }
        let axis: ViewNode.StackAxis = name == "VStack" ? .vertical : name == "HStack" ? .horizontal : .depth
        if call.arguments.isEmpty && axis != .depth {
            return .stack(axis: axis, children: children, modifiers: [], location: location(of: call))
        }
        var alignment: LayoutAlignment = .center
        var spacing: Expression? = axis == .depth ? nil : Expression(.numberLiteral(name == "HStack" ? "4" : "8"))
        for argument in call.arguments {
            switch argument.label?.text {
            case "alignment":
                guard let member = argument.expression.as(MemberAccessExprSyntax.self),
                      let value = LayoutAlignment(rawValue: member.declName.baseName.text) else {
                    error("RFVIEW003", "Stack alignment is outside the supported subset.", at: argument)
                    return nil
                }
                alignment = value
            case "spacing":
                guard axis != .depth else {
                    error("RFVIEW003", "ZStack does not accept spacing.", at: argument)
                    return nil
                }
                spacing = viewScalar(argument.expression)
            default:
                error("RFVIEW003", "Stack arguments must be alignment and spacing.", at: argument)
                return nil
            }
        }
        return .layout(LayoutContainer(axis: axis, alignment: alignment, spacing: spacing), children: children, modifiers: [], location: location(of: call))
    }

    private func scroll(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.isEmpty, let children = children(of: call.trailingClosure), children.count == 1 else {
            error("RFVIEW004", "ScrollView requires exactly one direct supported child.",
                  "Wrap the content in a supported stack", at: call)
            return nil
        }
        return .scroll(axis: .vertical, child: children[0], modifiers: [], location: location(of: call))
    }

    private func staticList(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.isEmpty, let children = children(of: call.trailingClosure) else { return nil }
        return .list(children: children.map { child in
            if case .section = child { return child }
            return .listItem(child: child, location: child.sourceLocation)
        }, modifiers: [], location: location(of: call))
    }

    private func section(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard let children = children(of: call.trailingClosure), call.arguments.count <= 1 else {
            error("RFVIEW004", "Section accepts an optional title and a supported child builder.", at: call)
            return nil
        }
        var title: Expression?
        if let argument = call.arguments.first {
            guard argument.label == nil, let text = stringLiteral(argument.expression) else {
                error("RFVIEW004", "Section title must be a string resource key or literal.", at: argument)
                return nil
            }
            title = Expression(.stringLiteral(text), location: location(of: argument.expression))
        }
        return .section(header: title, children: children, location: location(of: call))
    }

    private func image(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.count == 1, let argument = call.arguments.first,
              let name = stringLiteral(argument.expression), call.trailingClosure == nil else {
            error("RFVIEW004", "Image requires one literal application asset name or `systemName`.",
                  "Use Image(\"asset_name\") or Image(systemName: \"symbol\")", at: call)
            return nil
        }
        let kind: ImageSource.Kind = argument.label?.text == "systemName" ? .system : .application
        guard kind == .system || argument.label == nil else {
            error("RFVIEW004", "Image argument label is unsupported.", at: argument)
            return nil
        }
        return .image(source: ImageSource(kind: kind, name: name, location: location(of: call)), modifiers: [], location: location(of: call))
    }

    private func label(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.map(\.label?.text) == [nil, "systemImage"],
              let title = stringLiteral(call.arguments.first!.expression),
              let icon = stringLiteral(call.arguments.last!.expression) else { return nil }
        return .label(title: Expression(.stringLiteral(title)), image: ImageSource(kind: .system, name: icon), modifiers: [], location: location(of: call))
    }

    private func leaf(_ call: FunctionCallExprSyntax, _ node: ViewNode) -> ViewNode? {
        guard call.arguments.isEmpty, call.trailingClosure == nil else { return nil }
        return node
    }

    func viewScalar(_ expression: ExprSyntax) -> Expression {
        if let text = stringLiteral(expression) {
            return Expression(.stringLiteral(text), location: location(of: expression))
        }
        if let literal = expression.as(IntegerLiteralExprSyntax.self) {
            return Expression(.numberLiteral(literal.literal.text), location: location(of: expression))
        }
        if let literal = expression.as(FloatLiteralExprSyntax.self) {
            return Expression(.numberLiteral(literal.literal.text), location: location(of: expression))
        }
        if let literal = expression.as(BooleanLiteralExprSyntax.self) {
            return Expression(.boolLiteral(literal.literal.tokenKind == .keyword(.true)), location: location(of: expression))
        }
        return Expression(.reference(expression.trimmedDescription), location: location(of: expression))
    }
}
