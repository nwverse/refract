import RefractIR
import RefractMapping

enum ArkExpression {
    static func emit(_ expression: Expression, item: String? = nil, mapping: Mapping = .empty) throws -> String {
        switch expression.value {
        case let .stringLiteral(value):
            return try ArkText.string(value)
        case let .verbatimText(value):
            return try ArkText.string(value)
        case .localizedText:
            return try LocalizedTextEmitter.arkUI(expression, mapping: mapping) {
                try ArkExpression.emit($0, mapping: mapping)
            }
        case let .stringKey(key):
            let resource = try mapping.stringResource(key, platform: .harmonyOS, location: expression.location)
            return "$r('\(resource.namespace ?? "app").\(resource.table ?? "string").\(resource.nativeName)')"
        case let .boolLiteral(value):
            return value ? "true" : "false"
        case let .numberLiteral(value):
            guard Double(value) != nil else {
                throw Diagnostic(code: "arkui.invalid_number",
                                 message: "`\(value)` is not a supported finite ArkTS number literal.",
                                 suggestion: "Use a finite decimal integer or floating-point literal.",
                                 location: expression.location)
            }
            return value
        case let .reference(name):
            if let item, name == item || name.hasPrefix(item + ".") {
                return try referenceName(name, location: expression.location)
            }
            return "this.\(try referenceName(name, location: expression.location))"
        case .binding:
            throw Diagnostic(code: "arkui.unsupported_binding_projection",
                             message: "A projected binding needs a supported control or child component argument.",
                             suggestion: "Pass the binding to a supported binding-aware view.",
                             location: expression.location)
        case let .platformValue(alternatives):
            return try emit(alternatives.harmonyOS, item: item, mapping: mapping)
        case .valueProperty, .interpolatedString:
            throw Diagnostic(code: "arkui.unsupported_state_expression",
                             message: "This state expression requires the local-state lowering.",
                             suggestion: "Use a supported state read or interpolation.",
                             location: expression.location)
        }
    }

    static func assignment(_ binding: Expression, to value: String) throws -> String {
        guard case let .binding(name) = binding.value else {
            throw Diagnostic(code: "arkui.invalid_control_binding",
                             message: "An editable ArkUI control requires a local or parent-owned binding.",
                             suggestion: "Use a supported @State or @Binding projected value.",
                             location: binding.location)
        }
        return "this.\(try referenceName(name, location: binding.location)) = \(value)"
    }

    static func referenceName(_ expression: Expression) throws -> String {
        guard case let .reference(name) = expression.value else {
            throw Diagnostic(code: "arkui.unsupported_action",
                             message: "ArkUI event handlers require a resolved model action reference.",
                             suggestion: "Use a declared model action instead of arbitrary Swift statements.",
                             location: expression.location)
        }
        return try referenceName(name, location: expression.location)
    }

    private static func referenceName(_ name: String, location: RefractIR.SourceLocation?) throws -> String {
        guard !name.isEmpty, !name.hasPrefix("."), !name.hasSuffix("."), !name.contains(".."),
              name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy(ArkText.isIdentifier) else {
            throw Diagnostic(code: "arkui.invalid_reference",
                             message: "`\(name)` is not a supported typed member reference.",
                             suggestion: "Use a property or action on the declared component model.",
                             location: location)
        }
        return name
    }
}

enum ArkText {
    static func isIdentifier(_ value: String) -> Bool {
        guard let first = value.first, first.isLetter || first == "_" else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    static func isIdentifier(_ value: Substring) -> Bool {
        isIdentifier(String(value))
    }

    static func isResourceName(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
    }

    static func string(_ value: String) throws -> String {
        var result = "'"
        for character in value {
            switch character {
            case "\\": result += "\\\\"
            case "'": result += "\\'"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "$": result += "\\$"
            default:
                if character.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) {
                    throw Diagnostic(code: "arkui.unsupported_string_control_character",
                                     message: "Text contains a control character that ArkTS cannot represent directly.",
                                     suggestion: "Use a supported escaped string or a localized resource.")
                } else {
                    result.append(character)
                }
            }
        }
        return result + "'"
    }

    static func header(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.map {
            $0.value < 0x20 || $0.value == 0x7f ? UnicodeScalar(0x20)! : $0
        }))
    }
}
