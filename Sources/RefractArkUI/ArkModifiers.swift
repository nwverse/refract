import RefractIR

enum ArkModifiers {
    static func emit(_ modifiers: [Modifier], item: String? = nil) throws -> String {
        try modifiers.map { modifier in
            let arguments = modifier.arguments
            switch (modifier.name, arguments.count) {
            case ("padding", 0):
                return ".padding(0)"
            case ("padding", 1):
                return try attribute("padding", arguments[0], item: item)
            case ("opacity", 1), ("fontSize", 1), ("fontWeight", 1),
                 ("width", 1), ("height", 1):
                return try attribute(modifier.name, arguments[0], item: item)
            case ("background", 1):
                return try attribute("backgroundColor", arguments[0], item: item)
            case ("foregroundColor", 1), ("foregroundStyle", 1):
                return try attribute("fontColor", arguments[0], item: item)
            case ("cornerRadius", 1):
                return try attribute("borderRadius", arguments[0], item: item)
            default:
                throw Diagnostic(code: "arkui.unsupported_modifier",
                                 message: "Modifier `\(modifier.name)` with \(arguments.count) arguments has no exact ArkUI mapping.",
                                 suggestion: "Use a supported modifier with the documented argument types.",
                                 location: modifier.location)
            }
        }.joined()
    }

    private static func attribute(_ name: String, _ value: Expression, item: String?) throws -> String {
        ".\(name)(\(try ArkExpression.emit(value, item: item)))"
    }
}
