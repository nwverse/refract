import RefractIR
import SwiftSyntax

extension Builder {
    func localStateDeclarations(_ node: StructDeclSyntax) -> [StateDeclaration]? {
        var states: [StateDeclaration] = []
        for member in node.memberBlock.members {
            guard let declaration = member.decl.as(VariableDeclSyntax.self),
                  declaration.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text != "body"
            else { continue }
            guard declaration.attributes.count == 1,
                  let attribute = declaration.attributes.first?.as(AttributeSyntax.self),
                  attribute.attributeName.trimmedDescription == "State",
                  attribute.arguments == nil,
                  declaration.modifiers.contains(where: { $0.name.tokenKind == .keyword(.private) }),
                  declaration.bindingSpecifier.tokenKind == .keyword(.var),
                  declaration.bindings.count == 1, let binding = declaration.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let typeName = binding.typeAnnotation?.type.trimmedDescription,
                  let type = scalarType(typeName), let initial = binding.initializer,
                  let value = literal(initial.value, expected: type) else {
                error("state.invalid_declaration", "Stored View properties require one private @State scalar with a literal initializer.",
                      "Use `@State private var count: Int = 0`; bindings and models are implemented separately", at: member)
                return nil
            }
            states.append(.state(name: name, type: type, initialValue: value, location: location(of: declaration)))
        }
        return states
    }

    func stateText(_ expression: ExprSyntax) -> Expression? {
        guard let literal = expression.as(StringLiteralExprSyntax.self) else { return nil }
        if literal.segments.count == 1, case let .stringSegment(segment)? = literal.segments.first {
            return Expression(.stringLiteral(segment.content.text), location: location(of: expression))
        }
        var segments: [StringInterpolationSegment] = []
        for segment in literal.segments {
            switch segment {
            case let .stringSegment(text): segments.append(.literal(text.content.text))
            case let .expressionSegment(interpolation):
                guard interpolation.expressions.count == 1, let argument = interpolation.expressions.first,
                      argument.label == nil, let reference = argument.expression.as(DeclReferenceExprSyntax.self),
                      state(named: reference.baseName.text) != nil else {
                    error("state.invalid_projection", "Text interpolation requires a declared local state value.",
                          "Use `\\(property)` with a scalar @State property", at: interpolation)
                    return nil
                }
                segments.append(.expression(Expression(.valueProperty(.state(reference.baseName.text)),
                                                       location: location(of: reference))))
            }
        }
        return Expression(.interpolatedString(segments), location: location(of: expression))
    }

    func localStateAction(_ closure: ClosureExprSyntax?) -> StateAction? {
        guard let closure, !closure.statements.isEmpty else { return nil }
        guard closure.statements.count == 1, let statement = closure.statements.first,
              let expression = statement.item.as(ExprSyntax.self),
              let sequence = expression.as(SequenceExprSyntax.self), sequence.elements.count == 3 else {
            error("state.invalid_declaration", "A Button action requires one local state assignment.",
                  "Use `property = value` or `property += value`", at: closure)
            return nil
        }
        let elements = Array(sequence.elements)
        guard let reference = elements[0].as(DeclReferenceExprSyntax.self),
              let declaration = state(named: reference.baseName.text),
              case let .state(name, type, _, _) = declaration,
              let value = literal(elements[2], expected: type) else {
            error("state.invalid_projection", "A Button action must assign a declared scalar @State property.",
                  "Use a literal with the declared property type", at: expression)
            return nil
        }
        switch elements[1].trimmedDescription {
        case "=": return .assign(.state(name), value)
        case "+=" where type == .int || type == .double: return .increment(.state(name), value)
        default:
            error("state.invalid_declaration", "Only assignment and numeric += are supported for local state.",
                  "Use `property = value` or `property += value`", at: elements[1])
            return nil
        }
    }

    private func state(named name: String) -> StateDeclaration? {
        currentStates.first {
            if case let .state(declared, _, _, _) = $0 { return declared == name }
            return false
        }
    }

    private func literal(_ expression: ExprSyntax, expected: ValueType) -> Expression? {
        let at = location(of: expression)
        switch expected {
        case .string:
            guard let literal = expression.as(StringLiteralExprSyntax.self), literal.segments.count == 1,
                  case let .stringSegment(segment)? = literal.segments.first else { return nil }
            return Expression(.stringLiteral(segment.content.text), location: at)
        case .bool:
            guard let value = expression.as(BooleanLiteralExprSyntax.self) else { return nil }
            return Expression(.boolLiteral(value.literal.tokenKind == .keyword(.true)), location: at)
        case .int:
            guard let value = expression.as(IntegerLiteralExprSyntax.self) else { return nil }
            return Expression(.numberLiteral(value.literal.text), location: at)
        case .double:
            if let value = expression.as(FloatLiteralExprSyntax.self) {
                return Expression(.numberLiteral(value.literal.text), location: at)
            }
            if let value = expression.as(IntegerLiteralExprSyntax.self) {
                return Expression(.numberLiteral(value.literal.text), location: at)
            }
            return nil
        }
    }

    private func scalarType(_ name: String) -> ValueType? {
        switch name {
        case "String": .string
        case "Bool": .bool
        case "Int": .int
        case "Double": .double
        default: nil
        }
    }
}
