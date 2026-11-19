import RefractIR
import RefractMapping

extension ArkModifiers {
    static let accessibilityNames: Set<String> = [
        "nativeTestTag", "accessibilityLabel", "accessibilityHint", "accessibilityValue",
        "accessibilityAction", "accessibilityTraversal", "accessibilityIdentifier", "retainCallback",
    ]

    static func emitAccessibility(_ modifiers: [Modifier], item: String?, mapping: Mapping,
                                  traversal: AccessibilityTraversal?) throws -> String {
        var attributes: [String] = []
        var actions: [AccessibilityCustomAction] = []
        for modifier in modifiers {
            switch modifier.name {
            case "nativeTestTag":
                attributes.append(".id(\(try emitLocalExpression(try ModifierArguments(modifier: modifier).one(), item: item, mapping: mapping)))")
            case "accessibilityIdentifier":
                guard modifier.arguments.count == 1,
                      case let .stringLiteral(identifier) = modifier.arguments[0].value else {
                    throw ModifierArguments(modifier: modifier).invalid("Use a literal accessibility identifier.")
                }
                if let traversal {
                    attributes.append(".id('\(identifier)')")
                    for predecessor in traversal.steps where predecessor.after == identifier {
                        try requireMinimumAPI(mapping: mapping, minimum: 18, feature: "accessibilityNextFocusId", location: modifier.location)
                        attributes.append(".accessibilityNextFocusId('\(predecessor.name)')")
                    }
                }
            case "accessibilityLabel", "iosAccessibilityLabel":
                attributes.append(".accessibilityText(\(try emitLocalExpression(try ModifierArguments(modifier: modifier).one(), item: item, mapping: mapping)))")
            case "accessibilityHint":
                attributes.append(".accessibilityDescription(\(try emitLocalExpression(try ModifierArguments(modifier: modifier).one(), item: item, mapping: mapping)))")
            case "accessibilityValue":
                try requireMinimumAPI(mapping: mapping, minimum: 23, feature: "accessibilityStateDescription", location: modifier.location)
                attributes.append(".accessibilityStateDescription(\(try emitLocalExpression(try ModifierArguments(modifier: modifier).one(), item: item, mapping: mapping)))")
            case "accessibilityAction":
                guard modifier.arguments.count == 1, modifier.argumentLabels == ["named"],
                      case let .accessibilityAction(action) = modifier.arguments[0].value else {
                    throw ModifierArguments(modifier: modifier).invalid("Use a typed localized accessibility action.")
                }
                actions.append(action)
            case "accessibilityTraversal":
                break // The parent validates the sequence; its direct children carry the native links.
            case "retainCallback":
                throw Diagnostic(code: "RFNATIVE004",
                    message: "HarmonyOS callback retention requires a typed callback-identity representation.",
                    suggestion: "Use a direct typed callback; do not discard retention or add a runtime cache.", location: modifier.location)
            default: continue
            }
        }
        if !actions.isEmpty {
            try requireMinimumAPI(mapping: mapping, minimum: 26, feature: "accessibilityCustomActions", location: modifiers.first?.location)
            let rendered = try actions.map { action -> String in
                let label = try emitLocalExpression(action.label, item: item, mapping: mapping)
                let body = try emitLocalAction(action.action)
                return "  { name: \(label), onAction: () => { \(body) } }"
            }
            attributes.append(".accessibilityCustomActions([\n\(rendered.joined(separator: ",\n"))\n])")
        }
        guard !attributes.isEmpty else { return "" }
        let requiresMultiline = modifiers.contains {
            ["accessibilityHint", "accessibilityValue", "accessibilityAction", "accessibilityIdentifier"].contains($0.name)
        }
        return requiresMultiline ? "\n" + attributes.joined(separator: "\n") : attributes.joined()
    }

    static func validateAccessibilityTraversal(_ modifiers: [Modifier], children: [ViewNode],
                                               mapping: Mapping) throws -> AccessibilityTraversal? {
        guard let modifier = modifiers.first(where: { $0.name == "accessibilityTraversal" }),
              modifier.arguments.count == 1,
              case let .accessibilityTraversal(traversal) = modifier.arguments[0].value else { return nil }
        let identifiers = children.flatMap { child -> [String] in
            accessibilityModifiers(child).filter { $0.name == "accessibilityIdentifier" }.compactMap {
                guard $0.arguments.count == 1, case let .stringLiteral(name) = $0.arguments[0].value else { return nil }
                return name
            }
        }
        guard identifiers.count == Set(identifiers).count,
              Set(identifiers) == Set(traversal.steps.map(\.name)),
              identifiers.count == traversal.steps.count else {
            throw Diagnostic(code: "RFACCESS003", message: "Traversal order must include every named direct child exactly once.",
                suggestion: "Give each direct child one unique accessibilityIdentifier and list it in the parent's sequence.",
                location: modifier.location)
        }
        for (index, step) in traversal.steps.enumerated() {
            guard let after = step.after else { continue }
            guard traversal.steps[..<index].contains(where: { $0.name == after }) else {
                throw Diagnostic(code: "RFACCESS003", message: "An accessibility traversal predecessor must precede its dependent child.",
                    suggestion: "Use an acyclic source-order sequence with `after` naming an earlier child.", location: modifier.location)
            }
        }
        if traversal.steps.contains(where: { $0.after != nil }) {
            try requireMinimumAPI(mapping: mapping, minimum: 18, feature: "accessibilityNextFocusId", location: modifier.location)
        }
        return traversal
    }

    static func accessibilityModifiers(_ node: ViewNode) -> [Modifier] {
        switch node {
        case let .stack(_, _, modifiers, _), let .text(_, modifiers, _), let .button(_, _, modifiers, _),
             let .layout(_, _, modifiers, _), let .scroll(_, _, modifiers, _), let .list(_, modifiers, _),
             let .image(_, modifiers, _), let .toggle(_, _, modifiers, _, _, _), let .textInput(_, _, modifiers, _),
             let .label(_, _, modifiers, _), let .divider(modifiers, _):
            return modifiers
        default: return []
        }
    }

    private static func requireMinimumAPI(mapping: Mapping, minimum: Int, feature: String,
                                          location: SourceLocation?) throws {
        let actual = mapping.harmonyOS.minimumAPI
        guard let actual, actual >= minimum else {
            throw Diagnostic(code: "RFACCESS005",
                message: "\(feature) requires HarmonyOS API \(minimum) or later; the mapping declares \(actual.map(String.init) ?? "no minimumAPI").",
                suggestion: "Set `harmonyOS.minimumAPI` to the consuming app's supported API level, or remove this operation; no lower-version fallback is emitted.",
                location: location)
        }
    }
}
