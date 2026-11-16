import RefractIR
import RefractMapping

enum ArkModifiers {
    static func emit(_ modifiers: [Modifier], item: String? = nil, mapping: Mapping = .empty,
                     isText: Bool = false) throws -> String {
        guard item == nil, usesCanonicalValues(modifiers, mapping: mapping) else {
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
        let canonical = try emitCanonical(modifiers, mapping: mapping, isText: isText)
        if canonical.contains("\n") { return "\n" + canonical }
        return canonical
    }

    private static func usesCanonicalValues(_ modifiers: [Modifier], mapping: Mapping) -> Bool {
        modifiers.contains { modifier in
            if modifier.argumentLabels.contains(where: { $0 != nil }) { return true }
            return modifier.arguments.contains { expression in
                switch expression.value {
                case let .reference(name) where name.hasPrefix("Design"):
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
