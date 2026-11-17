import RefractIR

/// Emission for statically typed scalar values supplied by a mapped component or modifier.
public struct MappedExpression {
    public static func compose(_ expression: Expression, mapping: Mapping,
                        expected: ParameterType? = nil) throws -> String {
        switch expression.value {
        case let .stringLiteral(value):
            if expected == .stringKey {
                let resource = try mapping.stringResource(value, platform: .android, location: expression.location)
                guard resource.className != nil else {
                    throw Diagnostic(code: "R.string.not_configured", message: "The Android R class is missing.",
                                     suggestion: "Declare android.resources.className.", location: expression.location)
                }
                return "stringResource(R.string.\(resource.nativeName))"
            }
            return "\"\(value.escapedForMappedKotlin())\""
        case let .reference(reference):
            if reference.contains("(") {
                let allowed = reference.hasSuffix("()") && isIdentifierPath(String(reference.dropLast(2)))
                guard allowed else {
                    throw Diagnostic(code: "componentArgument", message: "`\(reference)` is not a supported action reference.",
                                     suggestion: "Use a no-argument model action reference.", location: expression.location)
                }
                return reference
            }
            if expected == .length || expected == .color || expected == .font {
                let category = try category(for: reference, mapping: mapping, expected: expected,
                                            location: expression.location)
                return try mapping.token(reference, category: category, platform: .android, location: expression.location)
            }
            guard isIdentifierPath(reference) else {
                throw Diagnostic(code: "componentArgument", message: "`\(reference)` is not a supported mapped value.",
                                 suggestion: "Use a supported scalar expression or declared token.", location: expression.location)
            }
            return reference
        case let .numberLiteral(value): return value
        case let .boolLiteral(value): return value ? "true" : "false"
        case let .valueProperty(.model(model, property)):
            return "\(model).\(property).value"
        case let .valueProperty(.state(name)), let .valueProperty(.binding(name)):
            return name
        case let .valueProperty(.itemBinding(binding)):
            return "\(binding.item).\(binding.property)"
        case .platformValue:
            throw Diagnostic(code: "componentArgument", message: "This mapped value needs a scalar platform selection.",
                             suggestion: "Use the interop scalar lowering for this argument.", location: expression.location)
        default:
            throw Diagnostic(code: "componentArgument", message: "This expression is not supported as a mapped value.",
                             suggestion: "Use a scalar, resource key or declared token.", location: expression.location)
        }
    }

    public static func arkUI(_ expression: Expression, mapping: Mapping,
                      expected: ParameterType? = nil) throws -> String {
        switch expression.value {
        case let .stringLiteral(value):
            if expected == .stringKey {
                let resource = try mapping.stringResource(value, platform: .harmonyOS, location: expression.location)
                guard let namespace = resource.namespace, let table = resource.table else {
                    throw Diagnostic(code: "R.string.not_configured", message: "The HarmonyOS resource namespace or table is missing.",
                                     suggestion: "Declare harmonyOS.resources.namespace and stringTable.", location: expression.location)
                }
                return "$r('\(namespace).\(table).\(resource.nativeName)')"
            }
            return "\"\(value.escapedForMappedArkTS())\""
        case let .reference(reference):
            if reference.contains("(") {
                let allowed = reference.hasSuffix("()") && isIdentifierPath(String(reference.dropLast(2)))
                guard allowed else {
                    throw Diagnostic(code: "componentArgument", message: "`\(reference)` is not a supported action reference.",
                                     suggestion: "Use a no-argument model action reference.", location: expression.location)
                }
                return reference
            }
            if expected == .length || expected == .color || expected == .font {
                let category = try category(for: reference, mapping: mapping, expected: expected,
                                            location: expression.location)
                return try mapping.token(reference, category: category, platform: .harmonyOS, location: expression.location)
            }
            guard isIdentifierPath(reference) else {
                throw Diagnostic(code: "componentArgument", message: "`\(reference)` is not a supported mapped value.",
                                 suggestion: "Use a supported scalar expression or declared token.", location: expression.location)
            }
            return reference
        case let .numberLiteral(value): return value
        case let .boolLiteral(value): return value ? "true" : "false"
        case let .valueProperty(.model(model, property)):
            return "this.\(model).\(property)"
        case let .valueProperty(.state(name)), let .valueProperty(.binding(name)):
            return "this.\(name)"
        case let .valueProperty(.itemBinding(binding)):
            return "\(binding.item).\(binding.property)"
        default:
            throw Diagnostic(code: "componentArgument", message: "This expression is not supported as a mapped value.",
                             suggestion: "Use a scalar, resource key or declared token.", location: expression.location)
        }
    }

    private static func category(for reference: String, mapping: Mapping, expected: ParameterType?,
                                 location: SourceLocation?) throws -> TokenCategory {
        let categories = TokenCategory.allCases.filter { mapping.android.tokens[$0][reference] != nil }
        guard categories.count == 1, let category = categories.first else {
            throw Diagnostic(code: "missingTokenMapping", message: "The token `\(reference)` is not declared in exactly one category.",
                             suggestion: "Declare the token in spacing, radius, font or color on both platforms.", location: location)
        }
        guard category.parameterType == expected else {
            throw Diagnostic(code: "componentArgument", message: "The token `\(reference)` has type \(category.parameterType.rawValue), not \(expected?.rawValue ?? "unknown").",
                             suggestion: "Use a token with the declared parameter type.", location: location)
        }
        return category
    }

    static func isIdentifierPath(_ value: String) -> Bool {
        !value.isEmpty && value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
            guard let first = part.first, first.isLetter || first == "_" else { return false }
            return part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        }
    }
}

private extension String {
    func escapedForMappedKotlin() -> String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    func escapedForMappedArkTS() -> String { escapedForMappedKotlin() }
}
