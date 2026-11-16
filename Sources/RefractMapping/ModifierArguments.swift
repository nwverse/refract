import RefractIR

/// Shared source semantics for modifier arguments, independent of either target's spelling.
struct ModifierArguments {
    let modifier: Modifier

    var labels: [String?] {
        guard !modifier.argumentLabels.isEmpty else { return Array(repeating: nil, count: modifier.arguments.count) }
        return modifier.argumentLabels
    }

    func one(label: String? = nil) throws -> Expression {
        guard modifier.arguments.count == 1, labels.count == 1, labels[0] == label else {
            throw invalid("Use one documented unlabeled modifier value.")
        }
        return modifier.arguments[0]
    }

    func zeroArguments() throws {
        guard modifier.arguments.isEmpty else { throw invalid("Use the modifier without arguments.") }
    }

    func labeled() throws -> [String: Expression] {
        guard modifier.arguments.count == labels.count else { throw invalid("Use labeled frame dimensions.") }
        var result: [String: Expression] = [:]
        for (label, argument) in zip(labels, modifier.arguments) {
            guard let label, result[label] == nil else { throw invalid("Use unique labeled frame dimensions.") }
            result[label] = argument
        }
        return result
    }

    func invalid(_ suggestion: String) -> Diagnostic {
        Diagnostic(code: "RFVIEW003",
                   message: "Modifier `\(modifier.name)` has unsupported argument labels or arity.",
                   suggestion: suggestion, location: modifier.location)
    }
}

struct ModifierValue {
    let expression: Expression
    let mapping: Mapping
    let location: SourceLocation?

    func number(allowInfinity: Bool = false) throws -> String {
        switch expression.value {
        case let .numberLiteral(value):
            guard let value = Double(value), value.isFinite else { throw invalid() }
            return value.formattedForModifier
        case let .reference(name) where allowInfinity && name == ".infinity":
            return "infinity"
        case let .platformValue(alternatives):
            return try ModifierValue(expression: alternatives.android, mapping: mapping, location: location)
                .number(allowInfinity: allowInfinity)
        default:
            throw invalid()
        }
    }

    func length(_ category: TokenCategory, platform: Platform) throws -> (value: String, isLiteral: Bool) {
        switch expression.value {
        case .numberLiteral:
            return (try number(), true)
        case let .reference(name) where name.contains("."):
            return (try mapping.token(name, category: category, platform: platform, location: location), false)
        case let .platformValue(alternatives):
            let branch = platform == .android ? alternatives.android : alternatives.harmonyOS
            return try ModifierValue(expression: branch, mapping: mapping, location: location)
                .length(category, platform: platform)
        default:
            throw invalid()
        }
    }

    private func invalid() -> Diagnostic {
        Diagnostic(code: "RFVIEW003",
                   message: "The modifier value is not a supported scalar or declared token.",
                   suggestion: "Use a finite numeric value or a mapping-declared token of the required category.",
                   location: location)
    }
}

private extension Double {
    var formattedForModifier: String {
        if rounded() == self, abs(self) < 1e15 { return String(Int(self)) }
        return String(self)
    }
}
