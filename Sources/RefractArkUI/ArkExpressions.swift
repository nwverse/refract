import RefractIR

enum ArkExpression {
    static func emit(_ expression: Expression) throws -> String {
        switch expression.value {
        case let .stringLiteral(value):
            return try ArkText.string(value)
        case let .stringKey(key):
            throw Diagnostic(code: "arkui.unresolved_string_resource",
                             message: "String resource `\(key)` has no validated ArkUI resource declaration.",
                             suggestion: "Declare the key in the localization resource mapping.",
                             location: expression.location)
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
            return "this.\(try referenceName(name, location: expression.location))"
        case .binding:
            throw Diagnostic(code: "arkui.unsupported_binding_projection",
                             message: "A projected binding needs a supported control or child component argument.",
                             suggestion: "Pass the binding to a supported binding-aware view.",
                             location: expression.location)
        }
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

    static func string(_ value: String) throws -> String {
        var result = "\""
        for character in value {
            switch character {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
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
        return result + "\""
    }

    static func header(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.map {
            $0.value < 0x20 || $0.value == 0x7f ? UnicodeScalar(0x20)! : $0
        }))
    }
}
