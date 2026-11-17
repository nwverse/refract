import RefractIR
import SwiftSyntax

extension Builder {
    func localInputStates(_ node: StructDeclSyntax) -> [StateDeclaration]? {
        var states: [StateDeclaration] = []
        let declaredModels = models
        for member in node.memberBlock.members {
            guard let declaration = member.decl.as(VariableDeclSyntax.self) else {
                error("RFVIEW006", "Only stored inputs and body belong in this child View slice.",
                      "Move other declarations into a model or a supported view body.", at: member)
                return nil
            }
            guard declaration.bindingSpecifier.tokenKind == .keyword(.let),
                  declaration.attributes.isEmpty,
                  declaration.bindings.count == 1,
                  let binding = declaration.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  name != "body",
                  itemTypes.contains(where: { $0.name == binding.typeAnnotation?.type.trimmedDescription }) == false else { continue }
            guard let typeName = binding.typeAnnotation?.type.trimmedDescription,
                  declaredModels.contains(where: { $0.name == typeName }) || declaredModelNames.contains(typeName),
                  binding.initializer == nil, binding.accessorBlock == nil else {
                error("state.invalid_declaration", "A model input must be a let property of a declared RefractModel protocol.",
                      "Use `let model: YourModel` with `protocol YourModel: RefractModel`", at: member)
                return nil
            }
            states.append(.model(ModelReference(propertyName: name, protocolName: typeName),
                                 location: location(of: declaration)))
        }
        return states
    }

    func localStateDeclarations(_ node: StructDeclSyntax) -> [StateDeclaration]? {
        var states: [StateDeclaration] = []
        for member in node.memberBlock.members {
            guard let declaration = member.decl.as(VariableDeclSyntax.self),
                  declaration.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text != "body"
            else { continue }
            if let annotation = declaration.bindings.first?.typeAnnotation?.type.as(ArrayTypeSyntax.self) {
                guard declaration.bindingSpecifier.tokenKind == .keyword(.var), declaration.attributes.count == 1,
                      declaration.attributes.first?.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "State",
                      declaration.modifiers.contains(where: { $0.name.tokenKind == .keyword(.private) }),
                      declaration.bindings.count == 1, let binding = declaration.bindings.first,
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let enumName = enums.first(where: { $0.name == annotation.element.trimmedDescription })?.name,
                      binding.initializer?.value.as(ArrayExprSyntax.self)?.elements.isEmpty == true else {
                    error("RFNAV002", "A navigation path must be `@State private var path: [Route] = []`.",
                          "Use a local no-payload Hashable destination enum and an empty path owned by the native host", at: member)
                    return nil
                }
                states.append(.navigationPath(name: name, enumName: enumName, location: location(of: declaration)))
                continue
            }
            if declaration.bindingSpecifier.tokenKind == .keyword(.let) {
                let binding = declaration.bindings.first
                if declaration.attributes.isEmpty,
                   let typeName = binding?.typeAnnotation?.type.trimmedDescription,
                   models.contains(where: { $0.name == typeName }) == false,
                   itemTypes.contains(where: { $0.name == typeName }) == false,
                   declaredModelNames.contains(typeName) == false {
                    continue
                }
                guard declaration.attributes.isEmpty, declaration.bindings.count == 1,
                      let binding = declaration.bindings.first,
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let typeName = binding.typeAnnotation?.type.trimmedDescription,
                      let contract = models.first(where: { $0.name == typeName }),
                      binding.initializer == nil, binding.accessorBlock == nil else {
                    error("state.invalid_declaration", "A model input must be a let property of a declared RefractModel protocol.",
                          "Use `let model: YourModel` with `protocol YourModel: RefractModel`", at: member)
                    return nil
                }
                states.append(.model(ModelReference(propertyName: name, protocolName: contract.name),
                                     location: location(of: declaration)))
                continue
            }
            guard declaration.attributes.count == 1,
                  let attribute = declaration.attributes.first?.as(AttributeSyntax.self),
                  ["State", "Binding"].contains(attribute.attributeName.trimmedDescription),
                  attribute.arguments == nil,
                  declaration.bindingSpecifier.tokenKind == .keyword(.var),
                  declaration.bindings.count == 1, let binding = declaration.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let typeName = binding.typeAnnotation?.type.trimmedDescription,
                  let type = scalarType(typeName) else {
                error("state.invalid_declaration", "Stored View properties require a supported scalar @State or @Binding declaration.",
                      "Use `@State private var count: Int = 0` or `@Binding var isEnabled: Bool`", at: member)
                return nil
            }
            let ownership = attribute.attributeName.trimmedDescription
            if ownership == "Binding" {
                guard binding.initializer == nil else {
                    error("state.binding_initializer", "@Binding property `\(name)` cannot have an independent initializer.",
                          "Pass the parent value and change callback instead", at: declaration)
                    return nil
                }
                states.append(.binding(name: name, type: type, location: location(of: declaration)))
                continue
            }
            guard ownership == "State",
                  declaration.modifiers.contains(where: { $0.name.tokenKind == .keyword(.private) }),
                  let initial = binding.initializer,
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
        if let property = modelProperty(expression) { return property }
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
                      let property = valueProperty(named: reference.baseName.text) else {
                    error("state.invalid_projection", "Text interpolation requires a declared local state or binding value.",
                          "Use `\\(property)` with a scalar @State or @Binding property", at: interpolation)
                    return nil
                }
                segments.append(.expression(Expression(.valueProperty(property),
                                                       location: location(of: reference))))
            }
        }
        return Expression(.interpolatedString(segments), location: location(of: expression))
    }

    func localStateAction(_ closure: ClosureExprSyntax?) -> StateAction? {
        guard let closure, !closure.statements.isEmpty else { return nil }
        if closure.statements.count == 1, let expression = closure.statements.first?.item.as(ExprSyntax.self),
           let action = modelAction(expression) {
            return action
        }
        guard closure.statements.count == 1, let statement = closure.statements.first,
              let expression = statement.item.as(ExprSyntax.self),
              let sequence = expression.as(SequenceExprSyntax.self), sequence.elements.count == 3 else {
            error("state.invalid_declaration", "A Button action requires one local state assignment.",
                  "Use `property = value` or `property += value`", at: closure)
            return nil
        }
        let elements = Array(sequence.elements)
        guard let reference = elements[0].as(DeclReferenceExprSyntax.self),
              let property = writableProperty(named: reference.baseName.text),
              let type = valueType(named: reference.baseName.text),
              let value = literal(elements[2], expected: type) else {
            error("state.invalid_projection", "A Button action must assign a declared scalar @State property.",
                  "Use a literal with the declared property type", at: expression)
            return nil
        }
        switch elements[1].trimmedDescription {
        case "=": return .assign(property, value)
        case "+=" where type == .int || type == .double: return .increment(property, value)
        default:
            error("state.invalid_declaration", "Only assignment and numeric += are supported for local state.",
                  "Use `property = value` or `property += value`", at: elements[1])
            return nil
        }
    }

    private func valueProperty(named name: String) -> ValueProperty? {
        for declaration in currentStates {
            switch declaration {
            case let .state(declared, _, _, _) where declared == name: return .state(name)
            case let .binding(declared, _, _) where declared == name: return .binding(name)
            default: continue
            }
        }
        return nil
    }

    private func writableProperty(named name: String) -> WritableProperty? {
        switch valueProperty(named: name) {
        case let .state(name): .state(name)
        case let .binding(name): .binding(name)
        default: nil
        }
    }

    private func valueType(named name: String) -> ValueType? {
        for declaration in currentStates {
            switch declaration {
            case let .state(declared, type, _, _) where declared == name: return type
            case let .binding(declared, type, _) where declared == name: return type
            default: continue
            }
        }
        return nil
    }

    func scalarType(_ name: String) -> ValueType? {
        switch name {
        case "String": .string
        case "Bool": .bool
        case "Int": .int
        case "Double": .double
        default: nil
        }
    }

    func literal(_ expression: ExprSyntax, expected: ValueType) -> Expression? {
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
}
