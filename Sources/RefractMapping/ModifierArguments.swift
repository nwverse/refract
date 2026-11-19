import RefractIR

/// Shared source semantics for modifier arguments, independent of either target's spelling.
public struct ModifierArguments {
    public let modifier: Modifier
    public init(modifier: Modifier) { self.modifier = modifier }

    public var labels: [String?] {
        guard !modifier.argumentLabels.isEmpty else { return Array(repeating: nil, count: modifier.arguments.count) }
        return modifier.argumentLabels
    }

    public func one(label: String? = nil) throws -> Expression {
        guard modifier.arguments.count == 1, labels.count == 1, labels[0] == label else {
            throw invalid("Use one documented unlabeled modifier value.")
        }
        return modifier.arguments[0]
    }

    public func labeled() throws -> [String: Expression] {
        guard modifier.arguments.count == labels.count else { throw invalid("Use labeled frame dimensions.") }
        var result: [String: Expression] = [:]
        for (label, argument) in zip(labels, modifier.arguments) {
            guard let label, result[label] == nil else { throw invalid("Use unique labeled frame dimensions.") }
            result[label] = argument
        }
        return result
    }

    public func invalid(_ suggestion: String) -> Diagnostic {
        Diagnostic(code: "RFVIEW003",
                   message: "Modifier `\(modifier.name)` has unsupported argument labels or arity.",
                   suggestion: suggestion, location: modifier.location)
    }
}

public struct ModifierValue {
    public let expression: Expression
    public let mapping: Mapping
    public let location: SourceLocation?

    public init(expression: Expression, mapping: Mapping, location: SourceLocation?) {
        self.expression = expression
        self.mapping = mapping
        self.location = location
    }

    public func number(allowInfinity: Bool = false, platform: Platform = .android) throws -> String {
        switch expression.value {
        case let .numberLiteral(value):
            guard let value = Double(value), value.isFinite else { throw invalid() }
            return value.formattedForModifier
        case let .reference(name) where allowInfinity && name == ".infinity":
            return "infinity"
        case let .platformValue(alternatives):
            let branch = platform == .android ? alternatives.android : alternatives.harmonyOS
            return try ModifierValue(expression: branch, mapping: mapping, location: location)
                .number(allowInfinity: allowInfinity, platform: platform)
        default:
            throw invalid()
        }
    }

    public func length(_ category: TokenCategory, platform: Platform) throws -> (value: String, isLiteral: Bool) {
        switch expression.value {
        case .numberLiteral:
            return (try number(), true)
        case let .reference(name) where name.contains("."):
            return (try mapping.token(name, category: category, platform: platform, location: location)
                .compose(location: location), false)
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
