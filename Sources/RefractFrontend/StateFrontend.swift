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
            if let typeName = declaration.bindings.first?.typeAnnotation?.type.trimmedDescription,
               let host = nativeHosts.first(where: { $0.name == typeName }) {
                guard declaration.bindingSpecifier.tokenKind == .keyword(.let), declaration.attributes.isEmpty,
                      declaration.modifiers.isEmpty, declaration.bindings.count == 1,
                      let binding = declaration.bindings.first, binding.initializer == nil, binding.accessorBlock == nil,
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                    error("RFHOST001", "A native host input must be an immutable let with its exact typed role protocol.",
                          "Use `let host: YourNotificationHost`; the app supplies the implementation", at: member)
                    return nil
                }
                states.append(.nativeHost(NativeHostReference(propertyName: name, protocolName: typeName,
                                                               capability: host.capability), location: location(of: declaration)))
                continue
            }
            if declaration.attributes.contains(where: {
                $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "RefractNativeValue"
            }) {
                continue
            }
            if let form = formState(declaration) {
                states.append(form)
                continue
            }
            if diagnostics.contains(where: { $0.code.hasPrefix("RFFORM") }) { return nil }
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
                  let typeName = binding.typeAnnotation?.type.trimmedDescription else {
                error("state.invalid_declaration", "Stored View properties require a supported scalar @State or @Binding declaration.",
                      "Use `@State private var count: Int = 0` or `@Binding var isEnabled: Bool`", at: member)
                return nil
            }
            let ownership = attribute.attributeName.trimmedDescription
            if let tabEnum = enums.first(where: { $0.name == typeName }), scalarType(typeName) == nil {
                guard ownership == "State", tabEnum.isNavigationDestination, tabEnum.payloadTypes.isEmpty,
                      declaration.modifiers.contains(where: { $0.name.tokenKind == .keyword(.private) }),
                      let initial = binding.initializer,
                      let member = initial.value.as(MemberAccessExprSyntax.self),
                      member.base == nil, tabEnum.cases.contains(member.declName.baseName.text) else {
                    error("RFNAV402", "A tab selection must be `@State private var tab: Tab = .home` over a no-payload Hashable enum.",
                          "Use one static enum case as the initial selection; the native host owns the selected tab", at: member)
                    return nil
                }
                states.append(.tabSelection(name: name, enumName: tabEnum.name, location: location(of: declaration)))
                continue
            }
            guard let type = scalarType(typeName) else {
                error("state.invalid_declaration", "Stored View properties require a supported scalar @State or @Binding declaration.",
                      "Use `@State private var count: Int = 0` or `@Binding var isEnabled: Bool`", at: member)
                return nil
            }
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

    /// `@State private var form = refractForm { ... }` or `@Binding var form: RefractForm`.
    /// Both ownerships lower the draft to per-field native values; only the write path differs.
    private func formState(_ declaration: VariableDeclSyntax) -> StateDeclaration? {
        guard declaration.bindingSpecifier.tokenKind == .keyword(.var),
              declaration.attributes.count == 1,
              let attribute = declaration.attributes.first?.as(AttributeSyntax.self),
              ["State", "Binding"].contains(attribute.attributeName.trimmedDescription),
              declaration.bindings.count == 1, let binding = declaration.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
        let ownership = attribute.attributeName.trimmedDescription
        let isFormCall = binding.initializer?.value.as(FunctionCallExprSyntax.self)?
            .calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "refractForm"
        let isFormType = binding.typeAnnotation?.type.trimmedDescription == "RefractForm"
        guard isFormCall || isFormType else { return nil }
        guard ownership != "Binding" || isFormType, ownership != "State" || isFormCall,
              declaration.modifiers.contains(where: { $0.name.tokenKind == .keyword(.private) }) == (ownership == "State"),
              attribute.arguments == nil else {
            error("state.invalid_declaration", "A form uses `@State private var form = refractForm { ... }` or `@Binding var form: RefractForm`.",
                  "Keep the draft in local state or pass the parent-owned form declaration", at: declaration)
            return nil
        }
        let initializer = binding.initializer?.value ?? ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("refractForm")))
        guard let declaration = formDeclaration(named: name, initializer: initializer, at: declaration) else { return nil }
        return .form(ownership: ownership == "State" ? .state : .binding, declaration: declaration,
                     location: declaration.location)
    }

    func stateText(_ expression: ExprSyntax) -> Expression? {
        if let property = modelProperty(expression) { return property }
        if expression.as(MemberAccessExprSyntax.self) != nil {
            return nativeValueProperty(expression)?.expression
        }
        guard let literal = expression.as(StringLiteralExprSyntax.self), literal.representedLiteralValue == nil else { return nil }
        if literal.segments.count == 1, case let .stringSegment(segment)? = literal.segments.first {
            return Expression(.stringLiteral(segment.content.text), location: location(of: expression))
        }
        var segments: [StringInterpolationSegment] = []
        for segment in literal.segments {
            switch segment {
            case let .stringSegment(text): segments.append(.literal(text.content.text))
            case let .expressionSegment(interpolation):
                guard interpolation.expressions.count == 1, let argument = interpolation.expressions.first,
                      argument.label == nil else {
                    error("state.invalid_projection", "Text interpolation requires one typed scalar value.",
                          "Use a scalar @State, @Binding, model or selected native correlation field", at: interpolation)
                    return nil
                }
                if let native = nativeValueProperty(argument.expression) {
                    guard native.type == .string || native.type == .int || native.type == .double else {
                        error("RFHOST005", "A native event state cannot be formatted as a scalar.",
                              "Use id or revision for native correlation interpolation", at: argument.expression)
                        return nil
                    }
                    segments.append(.expression(native.expression))
                    continue
                }
                guard let reference = argument.expression.as(DeclReferenceExprSyntax.self),
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
           let action = nativeHostAction(expression) {
            return action
        }
        if closure.statements.count == 1, let expression = closure.statements.first?.item.as(ExprSyntax.self),
           let action = formSubmit(expression) {
            return action
        }
        if diagnostics.contains(where: { $0.code == "RFFORM004" }) { return nil }
        if closure.statements.count == 1, let expression = closure.statements.first?.item.as(ExprSyntax.self),
           let action = modelAction(expression) {
            return action
        }
        guard closure.statements.count == 1, let statement = closure.statements.first,
              let expression = statement.item.as(ExprSyntax.self),
              let sequence = expression.as(SequenceExprSyntax.self), sequence.elements.count == 3 else {
            error("state.invalid_declaration", "A Button action requires one local state assignment.",
                  "Use `property = value`, `property += value`, or one typed native host request", at: closure)
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
        case .revision:
            error("RFMSG001", "A revision literal belongs only in the application's validated message projection.",
                  "Store the UInt64 revision in the ChatMessage item, not a generic scalar action", at: expression)
            return nil
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

    func hostLiteral(_ expression: ExprSyntax, expected: ValueType) -> Expression? {
        if let typed = scalar(expression) { return typed.type == expected ? typed.expression : nil }
        return literal(expression, expected: expected)
    }
}
