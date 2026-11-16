import RefractIR
import RefractMapping

enum ArkModifiers {
    static func emit(_ modifiers: [Modifier], item: String? = nil, mapping: Mapping = .empty,
                     isText: Bool = false) throws -> String {
        if modifiers.contains(where: {
            switch $0.name {
            case "nativeTestTag", "accessibilityLabel": true
            default: false
            }
        }) {
            return try modifiers.map { modifier in
                switch modifier.name {
                case "nativeTestTag":
                    return ".id(\(try ArkExpression.emit(try ModifierArguments(modifier: modifier).one(), item: item, mapping: mapping)))"
                case "accessibilityLabel":
                    return ".accessibilityText(\(try ArkExpression.emit(try ModifierArguments(modifier: modifier).one(), item: item, mapping: mapping)))"
                default:
                    throw Diagnostic(code: "RFNATIVE004",
                        message: "Modifier `\(modifier.name)` is not supported on an ArkUI toggle.",
                        suggestion: "Keep native measurement operations on the selected toggle control.",
                        location: modifier.location)
                }
            }.joined()
        }
        guard usesCanonicalValues(modifiers, mapping: mapping) else {
            return try modifiers.map { modifier in
                let arguments = modifier.arguments
                switch (modifier.name, arguments.count) {
                case ("padding", 0):
                    return ".padding(0)"
                case ("padding", 1):
                    return try attribute("padding", arguments[0], item: item, mapping: mapping)
                case ("opacity", 1), ("fontSize", 1), ("fontWeight", 1),
                     ("width", 1), ("height", 1):
                    return try attribute(modifier.name, arguments[0], item: item, mapping: mapping)
                case ("background", 1):
                    return try attribute("backgroundColor", arguments[0], item: item, mapping: mapping)
                case ("foregroundColor", 1), ("foregroundStyle", 1):
                    return try attribute("fontColor", arguments[0], item: item, mapping: mapping)
                case ("cornerRadius", 1):
                    return try attribute("borderRadius", arguments[0], item: item, mapping: mapping)
                default:
                    throw Diagnostic(code: "arkui.unsupported_modifier",
                        message: "Modifier `\(modifier.name)` with \(arguments.count) arguments has no exact ArkUI mapping.",
                        suggestion: "Use a supported modifier with the documented argument types.",
                        location: modifier.location)
                }
            }.joined()
        }
        let canonical = try emitCanonical(modifiers, mapping: mapping, item: item, isText: isText)
        if canonical.contains("\n") {
            let continuation = canonical.split(separator: "\n", omittingEmptySubsequences: false)
                .map { "\u{1}" + $0 }.joined(separator: "\n")
            return "\n" + continuation
        }
        return canonical
    }

    private static func usesCanonicalValues(_ modifiers: [Modifier], mapping: Mapping) -> Bool {
        if modifiers.contains(where: { ["font", "foregroundStyle", "frame", "background"].contains($0.name) }) { return true }
        return modifiers.contains { modifier in
            if modifier.argumentLabels.contains(where: { $0 != nil }) { return true }
            return modifier.arguments.contains { expression in
                switch expression.value {
                case let .reference(name):
                    return TokenCategory.allCases.contains { mapping.harmonyOS.tokens[$0][name] != nil }
                case .platformValue:
                    return true
                default:
                    return false
                }
            }
        }
    }

    private static func attribute(_ name: String, _ value: Expression, item: String?, mapping: Mapping) throws -> String {
        ".\(name)(\(try ArkExpression.emit(value, item: item, mapping: mapping)))"
    }
}
