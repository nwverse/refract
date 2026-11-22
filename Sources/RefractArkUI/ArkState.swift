import RefractIR
import RefractMapping

func emitNavigationOperation(_ operation: NavigationOperation, into writer: inout ArkWriter) throws {
    let name = operation.pathName
    writer.line("@Event on\(name.prefix(1).uppercased())\(name.dropFirst())Navigate: (destination: \(operation.enumName)) => void = (destination: \(operation.enumName)): void => {};")
    writer.line()
}

func emitLocalState(_ declaration: StateDeclaration, into writer: inout ArkWriter) throws {
    if case let .nativeHost(reference, _) = declaration {
        writer.line("@Require @Param \(reference.propertyName): \(reference.protocolName);")
        return
    }
    if case let .model(reference, _) = declaration {
        writer.line("@Require @Param \(reference.propertyName): \(reference.protocolName);")
        return
    }
    if case let .navigationPath(name, enumName, _) = declaration {
        writer.line("@Event on\(name.prefix(1).uppercased())\(name.dropFirst())Navigate: (destination: \(enumName)) => void = (destination: \(enumName)): void => {};")
        writer.line()
        return
    }
    if case let .tabSelection(name, enumName, _) = declaration {
        // The native host owns the selected tab; the generated component is controlled, never a second owner.
        writer.line("@Require @Param \(name): \(enumName);")
        writer.line("@Event on\(name.prefix(1).uppercased())\(name.dropFirst())Change: (value: \(enumName)) => void = (value: \(enumName)): void => {};")
        writer.line()
        return
    }
    if case let .binding(name, type, _) = declaration {
        let type = try stateType(type)
        writer.line("@Require @Param \(name): \(type);")
        writer.line("@Event on\(name.prefix(1).uppercased())\(name.dropFirst())Change: (value: \(type)) => void = (value: \(type)): void => {};")
        writer.line()
        return
    }
    if case let .form(ownership, declaration, _) = declaration {
        for field in declaration.fields {
            let name = declaration.name + field.name.prefix(1).uppercased() + String(field.name.dropFirst())
            let type = try stateType(field.type)
            switch ownership {
            case .state:
                writer.line("@Local private \(name): \(type) = \(try emitLocalExpression(field.initialValue));")
            case .binding:
                writer.line("@Require @Param \(name): \(type);")
                writer.line("@Event on\(name.prefix(1).uppercased())\(name.dropFirst())Change: (value: \(type)) => void = (value: \(type)): void => {};")
            }
        }
        writer.line()
        return
    }
    guard case let .state(name, type, initial, location) = declaration else {
        throw Diagnostic(code: "arkui.unsupported_state_declaration",
                         message: "Bindings and model inputs require their separate observation lowering.",
                         suggestion: "Use a supported local @State property or wait for binding/model support.")
    }
    guard let initial else {
        throw Diagnostic(code: "arkui.state_missing_initializer", message: "Local state `\(name)` needs an initializer.",
                         suggestion: "Initialize @State in the Swift declaration.", location: location)
    }
    writer.line("@Local private \(name): \(try stateType(type)) = \(try emitLocalExpression(initial));")
    writer.line()
}

private func stateType(_ type: ValueType) throws -> String {
    switch type {
    case .string: "string"
    case .bool: "boolean"
    case .int, .double: "number"
    case .revision:
        throw Diagnostic(code: "RFMSG001", message: "A message revision is item data, not mutable local state.",
                         suggestion: "Keep the UInt64 revision in the application-owned ChatMessage snapshot")
    }
}

func emitLocalExpression(_ expression: Expression, item: String? = nil,
                         mapping: Mapping = .empty, itemParameters: Set<String> = [],
                         localAliases: Set<String> = [], itemInputs: Set<String> = []) throws -> String {
    switch expression.value {
    case let .nativeValueProperty(value):
        return "this.\(value.value).\(value.field.rawValue)"
    case let .valueProperty(.state(name)), let .valueProperty(.binding(name)):
        guard ArkText.isIdentifier(name) else {
            throw Diagnostic(code: "arkui.invalid_reference", message: "`\(name)` is not a valid state identifier.",
                             suggestion: "Use a Swift identifier.", location: expression.location)
        }
        return "this.\(name)"
    case let .valueProperty(.model(model, property)):
        return "this.\(model).\(property)"
    case let .formField(form, field):
        guard ArkText.isIdentifier(form), ArkText.isIdentifier(field) else {
            throw Diagnostic(code: "arkui.invalid_reference", message: "A form field needs Swift identifiers.",
                             suggestion: "Use identifier field names in refractForm.", location: expression.location)
        }
        return "this.\(form)\(field.prefix(1).uppercased())\(field.dropFirst())"
    case let .presence(subject):
        let value = try emitLocalExpression(subject, item: item, mapping: mapping)
        return "(\(value) !== null && \(value) !== undefined)"
    case let .formValid(declaration):
        return try formGuard(declaration, item: item, mapping: mapping)
    case let .valueProperty(.itemBinding(binding)):
        guard item == binding.item || itemParameters.contains(binding.item) else {
            throw Diagnostic(code: "arkui.invalid_control_binding", message: "An item binding must read the current typed list item.",
                             suggestion: "Use the current LazyForEach item.", location: expression.location)
        }
        return "\(item != binding.item && itemInputs.contains(binding.item) ? "this." : "")\(binding.item).\(binding.property)"
    case let .interpolatedString(segments):
        var result = "`"
        for segment in segments {
            switch segment {
            case let .literal(text):
                result += try ArkText.string(text).dropFirst().dropLast()
            case let .expression(value):
                result += "${\(try emitLocalExpression(value, item: item))}"
            }
        }
        return result + "`"
    default:
        return try ArkExpression.emit(expression, item: item, mapping: mapping, localAliases: localAliases)
    }
}

func emitLocalAction(_ action: StateAction) throws -> String {
    switch action {
    case let .assign(.state(name), value): return "this.\(name) = \(try emitLocalExpression(value));"
    case let .increment(.state(name), value): return "this.\(name) += \(try emitLocalExpression(value));"
    case let .assign(.binding(name), value):
        return "this.on\(name.prefix(1).uppercased())\(name.dropFirst())Change(\(try emitLocalExpression(value)));"
    case let .increment(.binding(name), value):
        return "this.on\(name.prefix(1).uppercased())\(name.dropFirst())Change(this.\(name) + \(try emitLocalExpression(value)));"
    case let .modelMethod(model, name, arguments):
        let arguments = try arguments.map { try emitLocalExpression($0.value) }.joined(separator: ", ")
        return "this.\(model).\(name)(\(arguments));"
    case let .hostMethod(host, capability, name, arguments):
        return try emitArkNativeHostAction(host: host, capability: capability, name: name, arguments: arguments)
    case let .submit(submit):
        let arguments = try submit.arguments.map {
            try emitLocalExpression(Expression(.formField(form: submit.form, field: $0.field)))
        }.joined(separator: ", ")
        return "if (\(try formGuard(submit, item: nil, mapping: .empty))) { this.\(submit.model).\(submit.action)(\(arguments)); }"
    }
}

/// The same bounded rule vocabulary as the Compose guard, in ArkTS syntax. An empty rule set is
/// an unconditional submission; no runtime validator or reflection is involved.
func formGuard(_ form: FormDeclaration, item: String?, mapping: Mapping) throws -> String {
    var clauses: [String] = []
    for field in form.fields {
        let value = try emitLocalExpression(Expression(.formField(form: form.name, field: field.name)),
                                            item: item, mapping: mapping)
        for rule in field.rules {
            switch rule {
            case .nonEmpty:
                clauses.append("\(value).length > 0")
            case let .equals(other):
                let sibling = try emitLocalExpression(Expression(.formField(form: form.name, field: other)),
                                                      item: item, mapping: mapping)
                clauses.append("\(value) === \(sibling)")
            }
        }
    }
    return clauses.isEmpty ? "true" : clauses.joined(separator: " && ")
}

func formGuard(_ submit: FormSubmit, item: String?, mapping: Mapping) throws -> String {
    // The frontend has already checked every referenced field; the declaration travels with the IR.
    guard let declaration = submit.declaration else {
        throw Diagnostic(code: "RFFORM001", message: "Unknown form `\(submit.form)`.",
                         suggestion: "Declare the form in the view's state.", location: submit.location)
    }
    return try formGuard(declaration, item: item, mapping: mapping)
}
