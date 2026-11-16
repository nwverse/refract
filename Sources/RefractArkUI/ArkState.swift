import RefractIR
import RefractMapping

func emitLocalState(_ declaration: StateDeclaration, into writer: inout ArkWriter) throws {
    if case let .model(reference, _) = declaration {
        writer.line("@Require @Param \(reference.propertyName): \(reference.protocolName);")
        return
    }
    if case let .binding(name, type, _) = declaration {
        let type = try stateType(type)
        writer.line("@Require @Param \(name): \(type)")
        writer.line("@Event on\(name.prefix(1).uppercased())\(name.dropFirst())Change: (value: \(type)) => void = (value: \(type)): void => {}")
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
    writer.line("@Local private \(name): \(try stateType(type)) = \(try emitLocalExpression(initial))")
}

private func stateType(_ type: ValueType) throws -> String {
    switch type {
    case .string: "string"
    case .bool: "boolean"
    case .int, .double: "number"
    }
}

func emitLocalExpression(_ expression: Expression, item: String? = nil,
                         mapping: Mapping = .empty) throws -> String {
    switch expression.value {
    case let .valueProperty(.state(name)), let .valueProperty(.binding(name)):
        guard ArkText.isIdentifier(name) else {
            throw Diagnostic(code: "arkui.invalid_reference", message: "`\(name)` is not a valid state identifier.",
                             suggestion: "Use a Swift identifier.", location: expression.location)
        }
        return "this.\(name)"
    case let .valueProperty(.model(model, property)):
        return "this.\(model).\(property)"
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
        return try ArkExpression.emit(expression, item: item, mapping: mapping)
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
    }
}
