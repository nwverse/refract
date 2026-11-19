import RefractIR
import SwiftSyntax

/// View syntax additions. Unsupported shapes are diagnosed rather than lowered by spelling alone.
extension Builder {
    private static let extendedViews: Set<String> = ["VStack", "HStack", "ZStack", "ScrollView", "List", "Section", "Image", "Label", "Divider", "Spacer", "refractMarkdown"]

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
        case "refractMarkdown": return markdownDocument(call)
        default: return nil
        }
    }

    private func stack(_ call: FunctionCallExprSyntax) -> ViewNode? {
        let name = call.calledExpression.trimmedDescription
        guard let children = children(of: call.trailingClosure) else { return nil }
        let axis: ViewNode.StackAxis = name == "VStack" ? .vertical : name == "HStack" ? .horizontal : .depth
        if call.arguments.isEmpty && axis != .depth {
            return typedStack(axis: axis, alignment: nil, spacing: nil, children: children, location: location(of: call))
        }
        var alignment: LayoutAlignment?
        var spacing: Expression?
        var labels: Set<String> = []
        for argument in call.arguments {
            guard let label = argument.label?.text, labels.insert(label).inserted else {
                error("RFVIEW003", "Stack arguments must be unique, labeled alignment and spacing values.",
                      "Use the SwiftUI alignment and spacing labels.", at: argument)
                return nil
            }
            switch label {
            case "alignment":
                guard let member = argument.expression.as(MemberAccessExprSyntax.self), member.base == nil,
                      let value = LayoutAlignment(rawValue: member.declName.baseName.text),
                      Self.supportedAlignments(axis).contains(value) else {
                    error("RFVIEW003", "Stack alignment is unsupported for this container axis.",
                          "Use an alignment from the stack's documented alignment table.", at: argument)
                    return nil
                }
                alignment = value
            case "spacing":
                guard axis != .depth else {
                    error("RFVIEW003", "ZStack does not accept spacing.",
                          "Use spacing on VStack or HStack.", at: argument)
                    return nil
                }
                if let member = argument.expression.as(MemberAccessExprSyntax.self), member.base == nil,
                   let value = LayoutSpacing(rawValue: member.declName.baseName.text) {
                    spacing = Expression(.layoutSpacing(value), location: location(of: argument.expression))
                } else if argument.expression.as(IntegerLiteralExprSyntax.self) != nil ||
                            argument.expression.as(FloatLiteralExprSyntax.self) != nil {
                    // Existing SwiftUI numeric spacing stays scalar; the named form carries its own typed token.
                    spacing = viewScalar(argument.expression)
                } else {
                    error("RFVIEW003", "Stack spacing must be a scalar value, `.small`, or `.medium`.",
                          "Use a numeric spacing value or a documented spacing token.", at: argument)
                    return nil
                }
            default:
                error("RFVIEW003", "Stack arguments must be alignment and spacing.",
                      "Remove the unsupported stack argument.", at: argument)
                return nil
            }
        }
        return typedStack(axis: axis, alignment: alignment, spacing: spacing, children: children,
                          location: location(of: call))
    }

    private func typedStack(axis: ViewNode.StackAxis, alignment: LayoutAlignment?, spacing: Expression?,
                            children: [ViewNode], location: RefractIR.SourceLocation) -> ViewNode {
        if alignment == nil && spacing == nil {
            // Preserve the legacy native-default stack IR; no explicit 8 dp/fp gap is introduced.
            return .stack(axis: axis, children: children, modifiers: [], location: location)
        }
        return .layout(LayoutContainer(axis: axis, alignment: alignment, spacing: spacing),
                       children: children, modifiers: [], location: location)
    }

    private static func supportedAlignments(_ axis: ViewNode.StackAxis) -> Set<LayoutAlignment> {
        switch axis {
        case .vertical: [.center, .leading, .trailing]
        case .horizontal: [.center, .top, .bottom]
        case .depth: [.center, .topLeading, .bottomTrailing]
        }
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
        guard call.arguments.isEmpty else { return nil }
        guard call.additionalTrailingClosures.isEmpty else {
            error("RFVIEW004", "List accepts only its content trailing closure in v0.",
                  "Use List { ForEach(model.items) { item in ... } } or the documented static rows", at: call)
            return nil
        }
        let closure = call.trailingClosure
        let dynamicCalls = closure?.statements.compactMap { statement in
            statement.item.as(ExprSyntax.self).flatMap { forEachCall($0) }
        }
        if let forEach = dynamicCalls?.first ?? nil {
            guard closure?.statements.count == 1, dynamicCalls?.count == 1 else {
                error("RFLIST003", "Static and dynamic rows cannot be mixed in one List in v0.",
                      "Use List { ForEach(model.items) { item in ... } } alone, or a separate static List", at: forEach)
                return nil
            }
            if isMessageCollection(forEach.arguments.first?.expression) {
                return dynamicList(forEach)
            }
            return forEachList(forEach, owner: call)
        }
        guard let children = children(of: closure) else { return nil }
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
            if argument.label?.text == "verbatim" {
                guard let text = argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
                    error("RFVIEW004", "A verbatim Section title must be a literal without interpolation.", at: argument)
                    return nil
                }
                title = Expression(.verbatimText(text), type: .string, location: location(of: argument.expression))
            } else {
                guard argument.label == nil else {
                    error("RFVIEW004", "Section title must be a static localization key or explicit verbatim text.", at: argument)
                    return nil
                }
                var parser = LocalizationFrontend(file: file, converter: converter, scalar: {
                    TypedExpression(self.viewScalar($0), nil)
                }, stateText: stateText)
                guard let text = parser.localized(argument.expression) else {
                    diagnostics.append(contentsOf: parser.diagnostics)
                    return nil
                }
                title = text
            }
        }
        return .section(header: title, children: children, location: location(of: call))
    }

    private func image(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.count == 1 || call.arguments.count == 2,
              let first = call.arguments.first, let name = stringLiteral(first.expression),
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else {
            error("RFVIEW004", "Image requires a literal application asset name with an optional localized label.",
                  "Use Image(\"asset_name\", label: Text(\"accessibility.key\")) or Image(systemName: \"symbol\")", at: call)
            return nil
        }
        let kind: ImageSource.Kind = first.label?.text == "systemName" ? .system : .application
        guard kind == .system || first.label == nil else {
            error("RFVIEW004", "Image argument label is unsupported.", at: first)
            return nil
        }
        var description: Expression?
        if call.arguments.count == 2 {
            guard call.arguments.count == 2, kind == .application,
                  let label = call.arguments.last, label.label?.text == "label",
                  let text = label.expression.as(FunctionCallExprSyntax.self),
                  text.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Text",
                  text.arguments.count == 1, text.arguments.first?.label == nil,
                  text.trailingClosure == nil else {
                error("RFVIEW004", "Image accessibility requires a localized Text label.",
                      "Use label: Text(\"canonical.accessibility.key\")", at: call)
                return nil
            }
            var parser = LocalizationFrontend(file: file, converter: converter, scalar: {
                TypedExpression(self.viewScalar($0), nil)
            }, stateText: stateText)
            guard let title = parser.localized(text.arguments.first!.expression) else {
                diagnostics.append(contentsOf: parser.diagnostics)
                return nil
            }
            diagnostics.append(contentsOf: parser.diagnostics)
            description = title
        }
        return .image(source: ImageSource(kind: kind, name: name, location: location(of: call),
                                         contentDescription: description),
                      modifiers: [], location: location(of: call))
    }

    private func label(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.map(\.label?.text) == [nil, "systemImage"] ||
                call.arguments.map(\.label?.text) == ["verbatim", "systemImage"],
              let titleArgument = call.arguments.first?.expression,
              let icon = stringLiteral(call.arguments.last!.expression) else { return nil }
        if call.arguments.first?.label?.text == "verbatim" {
            guard let titleArgument = titleArgument.as(StringLiteralExprSyntax.self),
                  let text = titleArgument.representedLiteralValue else { return nil }
            return .label(title: Expression(.verbatimText(text), type: .string, location: location(of: call)),
                          image: ImageSource(kind: .system, name: icon), modifiers: [], location: location(of: call))
        }
        var parser = LocalizationFrontend(file: file, converter: converter, scalar: {
            TypedExpression(self.viewScalar($0), nil)
        }, stateText: stateText)
        guard let title = parser.localized(titleArgument) else {
            diagnostics.append(contentsOf: parser.diagnostics)
            return nil
        }
        diagnostics.append(contentsOf: parser.diagnostics)
        return .label(title: title, image: ImageSource(kind: .system, name: icon), modifiers: [], location: location(of: call))
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
