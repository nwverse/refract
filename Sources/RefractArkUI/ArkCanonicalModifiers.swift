import RefractIR
import RefractMapping

extension ArkModifiers {
    static func emitCanonical(_ modifiers: [Modifier], mapping: Mapping, item: String? = nil,
                              isText: Bool = false) throws -> String {
        var parts: [String] = []
        var index = 0
        while index < modifiers.count {
            let modifier = modifiers[index]
            let arguments = ModifierArguments(modifier: modifier)
            switch modifier.name {
            case "padding":
                if modifier.arguments.isEmpty {
                    parts.append(".padding(0)")
                } else if modifier.arguments.count == 1 {
                    parts.append(".padding(\(try length(try arguments.one(), category: .spacing, mapping: mapping)))")
                } else {
                    let values = try arguments.labeled()
                    if modifier.argumentLabels.allSatisfy({ $0 != nil }),
                       Set(values.keys).isSubset(of: ["horizontal", "vertical", "value"]),
                       values.count == 2 || values.count == 4 {
                        var edges: [String] = []
                        for (key, sides) in [("horizontal", ["left", "right"]), ("vertical", ["top", "bottom"])]
                        where values[key] != nil {
                            let value = try length(values[key]!, category: .spacing, mapping: mapping)
                            edges.append(contentsOf: sides.map { "\($0): \(value)" })
                        }
                        parts.append(".padding({ \(edges.joined(separator: ", ")) })")
                    } else {
                    guard values.count == 2, let amount = values["value"],
                          let axis = values["horizontal"] ?? values["vertical"] else {
                        throw arguments.invalid("Use horizontal or vertical edge insets with one spacing value.")
                    }
                    let horizontal = values["horizontal"] != nil
                    guard case let .reference(name) = axis.value,
                          name == (horizontal ? ".horizontal" : ".vertical") else {
                        throw arguments.invalid("Use the matching horizontal or vertical edge set.")
                    }
                    let value = try length(amount, category: .spacing, mapping: mapping)
                        parts.append(horizontal
                            ? ".padding({ left: \(value), right: \(value) })"
                            : ".padding({ top: \(value), bottom: \(value) })")
                    }
                }
            case "frame":
                let values = try arguments.labeled()
                guard !values.isEmpty, Set(values.keys).isSubset(of: ["width", "height", "maxWidth", "maxHeight"]) else {
                    throw arguments.invalid("Use fixed width/height or infinite maximum dimensions.")
                }
                for key in ["maxWidth", "maxHeight"] where values[key] != nil {
                    guard try ModifierValue(expression: values[key]!, mapping: mapping, location: modifier.location)
                        .number(allowInfinity: true, platform: .harmonyOS) == "infinity" else {
                        throw arguments.invalid("Only infinite maximum dimensions are supported.")
                    }
                }
                if values.keys.contains(where: { $0 == "width" || $0 == "height" }) {
                    guard values["maxWidth"] == nil, values["maxHeight"] == nil else {
                        throw arguments.invalid("Use either fixed or infinite dimensions in one frame.")
                    }
                    if let width = values["width"] {
                        parts.append(".width(\(try length(width, category: .spacing, mapping: mapping)))")
                    }
                    if let height = values["height"] {
                        parts.append(".height(\(try length(height, category: .spacing, mapping: mapping)))")
                    }
                } else {
                    if values["maxWidth"] != nil { parts.append(".width('100%')") }
                    if values["maxHeight"] != nil { parts.append(".height('100%')") }
                }
            case "background":
                parts.append(".backgroundColor(\(try token(try arguments.one(), category: .color, mapping: mapping)))")
            case "cornerRadius":
                let mappedToken: Bool
                if case let .reference(name) = try arguments.one().value {
                    mappedToken = mapping.harmonyOS.tokens.radius[name] != nil
                } else {
                    mappedToken = false
                }
                if mappedToken {
                    guard index > 0, modifiers[index - 1].name == "background" else {
                        throw Diagnostic(code: "RFVIEW003",
                            message: "A corner radius must follow its background to preserve rounded-background semantics.",
                            suggestion: "Use `.background(...).cornerRadius(...)` in that source order.",
                            location: modifier.location)
                    }
                }
                parts.append(".borderRadius(\(try length(try arguments.one(), category: .radius, mapping: mapping)))")
            case "opacity":
                let value = try ModifierValue(expression: try arguments.one(), mapping: mapping,
                                              location: modifier.location).number(platform: .harmonyOS)
                guard let opacity = Double(value), (0...1).contains(opacity) else {
                    throw Diagnostic(code: "RFVIEW003", message: "Opacity must be between zero and one.",
                                     suggestion: "Use a finite opacity in the inclusive range 0...1.", location: modifier.location)
                }
                parts.append(".opacity(\(value))")
            case "fontSize", "fontWeight", "width", "height":
                guard modifier.arguments.count == 1 else { throw arguments.invalid("Use one scalar attribute value.") }
                parts.append(".\(modifier.name)(\(try ArkExpression.emit(try arguments.one(), item: item, mapping: mapping)))")
            case "font":
                guard isText else {
                    throw Diagnostic(code: "RFVIEW003",
                        message: "Text styling cannot be attached to this non-Text view without changing its semantics.",
                        suggestion: "Apply `font` directly to the Text view.", location: modifier.location)
                }
                parts.append(".font(\(try token(try arguments.one(), category: .font, mapping: mapping)))")
            case "foregroundStyle", "foregroundColor":
                guard isText else {
                    throw Diagnostic(code: "RFVIEW003",
                        message: "Text styling cannot be attached to this non-Text view without changing its semantics.",
                        suggestion: "Apply `\(modifier.name)` directly to the Text view.",
                        location: modifier.location)
                }
                parts.append(".fontColor(\(try color(try arguments.one(), item: item, mapping: mapping)))")
            default:
                throw Diagnostic(code: "RFVIEW003", message: "Modifier `\(modifier.name)` has no ArkUI mapping.",
                                 suggestion: "Use a supported modifier or a typed native component.", location: modifier.location)
            }
            index += 1
        }
        return parts.joined(separator: "\n")
    }

    private static func length(_ expression: Expression, category: TokenCategory, mapping: Mapping) throws -> String {
        try ModifierValue(expression: expression, mapping: mapping, location: expression.location)
            .length(category, platform: .harmonyOS).value
    }

    private static func color(_ expression: Expression, item: String? = nil, mapping: Mapping) throws -> String {
        if case let .reference(name) = expression.value,
           mapping.harmonyOS.tokens.color[name] != nil {
            return try mapping.token(name, category: .color, platform: .harmonyOS, location: expression.location)
        }
        return try ArkExpression.emit(expression, item: item, mapping: mapping)
    }

    private static func token(_ expression: Expression, category: TokenCategory, mapping: Mapping) throws -> String {
        guard case let .reference(name) = expression.value, name.contains(".") else {
            throw Diagnostic(code: "RFVIEW003", message: "This modifier requires a declared design token.",
                             suggestion: "Use a token in the mapping's \(category.rawValue) category.", location: expression.location)
        }
        return try mapping.token(name, category: category, platform: .harmonyOS, location: expression.location)
    }
}
