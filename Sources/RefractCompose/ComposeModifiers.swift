import RefractIR
import RefractMapping

extension ComposeBackend {
    func modifierChain(_ modifiers: [Modifier], isRoot: Bool, isText: Bool = false, context: inout Context) throws -> String {
        var parts: [String] = []
        var index = 0
        while index < modifiers.count {
            let modifier = modifiers[index]
            switch modifier.name {
            case "font", "foregroundColor", "foregroundStyle":
                guard isText else {
                    throw Diagnostic(code: "RFVIEW003",
                        message: "Text styling cannot be attached to this non-Text view without changing its semantics.",
                        suggestion: "Apply `\(modifier.name)` directly to the Text view.",
                        location: modifier.location)
                }
                index += 1
                continue
            case "padding":
                let arguments = try ModifierArguments(modifier: modifier).labeled()
                if modifier.argumentLabels.allSatisfy({ $0 == "horizontal" || $0 == "vertical" || $0 == "value" }),
                   Set(arguments.keys).isSubset(of: ["horizontal", "vertical", "value"]),
                   arguments.count == 2 || arguments.count == 4 {
                    context.imports.insert("androidx.compose.foundation.layout.padding")
                    var directional: [String] = []
                    for key in ["horizontal", "vertical"] where arguments[key] != nil {
                        directional.append("\(key) = \(try composeLength(arguments[key]!, category: .spacing, context: &context))")
                    }
                    parts.append(".padding(\(directional.joined(separator: ", ")))")
                } else if modifier.arguments.isEmpty {
                    context.imports.insert("androidx.compose.ui.unit.dp")
                    parts.append(".padding(all = 16.dp)")
                } else if modifier.arguments.count == 1 {
                    let rendered = try composeLength(try ModifierArguments(modifier: modifier).one(),
                                                      category: .spacing, context: &context)
                    parts.append(".padding(all = \(rendered))")
                } else {
                    let arguments = try ModifierArguments(modifier: modifier).labeled()
                    guard arguments.count == 2, let axis = arguments["edges"] ?? arguments["horizontal"] ?? arguments["vertical"],
                          let amount = arguments["value"] else {
                        throw ModifierArguments(modifier: modifier).invalid(
                            "Use `.padding(.horizontal, value)` or `.padding(.vertical, value)`.")
                    }
                    let axisName: String
                    if arguments["horizontal"] != nil {
                        guard arguments.count == 2, case let .reference(name) = axis.value,
                              name == ".horizontal" || name == "Edge.Set.horizontal" else {
                            throw ModifierArguments(modifier: modifier).invalid("Use horizontal edge insets.")
                        }
                        axisName = "horizontal"
                    } else if arguments["vertical"] != nil {
                        guard arguments.count == 2, case let .reference(name) = axis.value,
                              name == ".vertical" || name == "Edge.Set.vertical" else {
                            throw ModifierArguments(modifier: modifier).invalid("Use vertical edge insets.")
                        }
                        axisName = "vertical"
                    } else {
                        throw ModifierArguments(modifier: modifier).invalid(
                            "Use `.padding(.horizontal, value)` or `.padding(.vertical, value)`.")
                    }
                    parts.append(".padding(\(axisName) = \(try composeLength(amount, category: .spacing, context: &context)))")
                }
            case "frame":
                let arguments = try ModifierArguments(modifier: modifier).labeled()
                guard !arguments.isEmpty, Set(arguments.keys).isSubset(of: ["width", "height", "maxWidth", "maxHeight"]) else {
                    throw ModifierArguments(modifier: modifier).invalid(
                        "Use fixed width/height or `.infinity` for maxWidth/maxHeight.")
                }
                for key in ["maxWidth", "maxHeight"] where arguments[key] != nil {
                    guard try ModifierValue(expression: arguments[key]!, mapping: context.mapping,
                                            location: modifier.location).number(allowInfinity: true, platform: .android) == "infinity" else {
                        throw ModifierArguments(modifier: modifier).invalid("Only infinite maximum dimensions are supported.")
                    }
                }
                if arguments.keys.contains(where: { $0 == "width" || $0 == "height" }) {
                    guard arguments["maxWidth"] == nil, arguments["maxHeight"] == nil else {
                        throw ModifierArguments(modifier: modifier).invalid(
                            "Use either fixed width/height or infinite maximum dimensions in one frame.")
                    }
                    var dimensions: [String] = []
                    for key in ["width", "height"] {
                        guard let value = arguments[key] else { continue }
                        dimensions.append("\(key) = \(try composeLength(value, category: .spacing, context: &context))")
                    }
                    if dimensions.count == 1, let width = arguments["width"] {
                        context.imports.insert("androidx.compose.foundation.layout.width")
                        parts.append(".width(\(try composeLength(width, category: .spacing, context: &context)))")
                    } else if dimensions.count == 1, let height = arguments["height"] {
                        context.imports.insert("androidx.compose.foundation.layout.height")
                        parts.append(".height(\(try composeLength(height, category: .spacing, context: &context)))")
                    } else {
                        context.imports.insert("androidx.compose.foundation.layout.size")
                        parts.append(".size(\(dimensions.joined(separator: ", ")))")
                    }
                } else {
                    if arguments["maxWidth"] != nil {
                        context.imports.insert("androidx.compose.foundation.layout.fillMaxWidth")
                        parts.append(".fillMaxWidth()")
                    }
                    if arguments["maxHeight"] != nil {
                        context.imports.insert("androidx.compose.foundation.layout.fillMaxHeight")
                        parts.append(".fillMaxHeight()")
                    }
                }
            case "background":
                context.imports.insert("androidx.compose.foundation.background")
                let color = try composeToken(try ModifierArguments(modifier: modifier).one(),
                                             category: .color, context: &context)
                if index + 1 < modifiers.count, modifiers[index + 1].name == "cornerRadius" {
                    let radius = try composeLength(try ModifierArguments(modifier: modifiers[index + 1]).one(),
                                                   category: .radius, context: &context)
                    context.imports.insert("androidx.compose.foundation.shape.RoundedCornerShape")
                    parts.append(".background(\(color), RoundedCornerShape(\(radius)))")
                    index += 1
                } else {
                    context.imports.insert("androidx.compose.foundation.background")
                    parts.append(".background(\(color))")
                }
            case "cornerRadius":
                throw Diagnostic(code: "RFVIEW003",
                    message: "A corner radius without a preceding background has ambiguous clipping semantics.",
                    suggestion: "Use `.background(...).cornerRadius(...)` in that source order.",
                    location: modifier.location)
            case "opacity":
                let value = try ModifierValue(expression: try ModifierArguments(modifier: modifier).one(),
                                              mapping: context.mapping, location: modifier.location).number(platform: .android)
                guard let opacity = Double(value), (0...1).contains(opacity) else {
                    throw Diagnostic(code: "RFVIEW003", message: "Opacity must be between zero and one.",
                                     suggestion: "Use a finite opacity in the inclusive range 0...1.", location: modifier.location)
                }
                context.imports.insert("androidx.compose.ui.draw.alpha")
                parts.append(".alpha(\(value)f)")
            case "nativeTestTag":
                context.imports.insert("androidx.compose.ui.platform.testTag")
                parts.append(".testTag(\(try renderExpression(try ModifierArguments(modifier: modifier).one(), context: &context)))")
            case "nativeContentDescription":
                context.imports.insert("androidx.compose.ui.semantics.contentDescription")
                context.imports.insert("androidx.compose.ui.semantics.semantics")
                parts.append(".semantics { contentDescription = \(try renderExpression(try ModifierArguments(modifier: modifier).one(), context: &context)) }")
            case "retainCallback":
                index += 1
                continue
            case "accessibilityLabel":
                throw Diagnostic(code: "RFNATIVE004",
                    message: "An iOS SwiftUI accessibility modifier cannot be emitted as an Android measurement hook.",
                    suggestion: "Use `.contentDescription` in the Android branch of the explicit platform alternative.",
                    location: modifier.location)
            default:
                throw Diagnostic(code: "RFVIEW003", message: "Modifier `\(modifier.name)` has no Compose mapping.",
                                 suggestion: "Use a supported modifier or a typed native component.", location: modifier.location)
            }
            index += 1
        }
        let base = isRoot ? "modifier" : "Modifier"
        return base + parts.joined()
    }

    func textSpecificModifiers(_ modifiers: [Modifier], context: inout Context) throws -> [String] {
        try modifiers.compactMap { modifier in
            switch modifier.name {
            case "font":
                let font = try composeToken(try ModifierArguments(modifier: modifier).one(),
                                            category: .font, context: &context)
                return "style = \(font)"
            case "foregroundColor", "foregroundStyle":
                let color = try composeToken(try ModifierArguments(modifier: modifier).one(),
                                             category: .color, context: &context)
                return "color = \(color)"
            default:
                return nil
            }
        }
    }

    private func composeLength(_ expression: Expression, category: TokenCategory,
                               context: inout Context) throws -> String {
        let value = try ModifierValue(expression: expression, mapping: context.mapping,
                                      location: expression.location).length(category, platform: .android)
        if value.isLiteral { context.imports.insert("androidx.compose.ui.unit.dp") }
        return value.isLiteral ? "\(value.value).dp" : value.value
    }

    func composeToken(_ expression: Expression, category: TokenCategory,
                              context: inout Context) throws -> String {
        guard case let .reference(name) = expression.value, name.contains(".") else {
            throw Diagnostic(code: "RFVIEW003", message: "This modifier requires a declared design token.",
                             suggestion: "Use a token in the mapping's \(category.rawValue) category.", location: expression.location)
        }
        return try context.mapping.token(name, category: category, platform: .android, location: expression.location)
    }
}
