import RefractIR
import RefractMapping

extension ComposeBackend {
    /// Resource lookup happens in composition; the semantics/action lambdas only read remembered Strings.
    func composeAccessibilitySemantics(_ modifiers: [Modifier], isRoot: Bool,
                                       into out: inout KotlinWriter, context: inout Context) throws -> String {
        var descriptions: [String] = []
        var value: String?
        var actions: [AccessibilityCustomAction] = []
        var identifier: String?
        for modifier in modifiers {
            if modifier.name == "accessibilityLabel" &&
                modifier.arguments.contains(where: { if case .stringLiteral = $0.value { true } else { false } }) {
                throw Diagnostic(code: "RFNATIVE004",
                    message: "A native iOS accessibility label cannot be emitted on Android.",
                    suggestion: "Keep it in the explicit iOS branch, or use localized Text in the shared accessibility contract.",
                    location: modifier.location)
            }
            switch modifier.name {
            case "accessibilityLabel", "accessibilityHint":
                descriptions.append(try rememberAccessibilityText(
                    try ModifierArguments(modifier: modifier).one(), named: modifier.name,
                    isRoot: isRoot, into: &out, context: &context))
            case "accessibilityValue":
                value = try rememberAccessibilityText(try ModifierArguments(modifier: modifier).one(),
                    named: "accessibilityValue", isRoot: isRoot, into: &out, context: &context)
            case "accessibilityAction":
                guard modifier.arguments.count == 1, modifier.argumentLabels == ["named"],
                      case let .accessibilityAction(action) = modifier.arguments[0].value else {
                    throw ModifierArguments(modifier: modifier).invalid("Use a typed localized accessibility action.")
                }
                actions.append(action)
            case "accessibilityIdentifier":
                guard modifier.arguments.count == 1, case let .stringLiteral(name) = modifier.arguments[0].value else {
                    throw ModifierArguments(modifier: modifier).invalid("Use a literal accessibility identifier.")
                }
                identifier = name
            case "accessibilityTraversal": break
            default: continue
            }
        }
        var statements: [String] = []
        if !descriptions.isEmpty {
            context.imports.insert("androidx.compose.ui.semantics.contentDescription")
            statements.append("contentDescription = \(descriptions.joined(separator: " + \" \" + "))")
        }
        if let identifier {
            context.imports.insert("androidx.compose.ui.semantics.testTag")
            statements.append("testTag = \"\(identifier)\"")
            if let traversal = context.accessibilityTraversal,
               let index = traversal.steps.firstIndex(where: { $0.name == identifier }) {
                context.imports.insert("androidx.compose.ui.semantics.isTraversalGroup")
                context.imports.insert("androidx.compose.ui.semantics.traversalIndex")
                statements.append("isTraversalGroup = true")
                statements.append("traversalIndex = \(index)f")
            }
        }
        if let value {
            context.imports.insert("androidx.compose.ui.semantics.stateDescription")
            statements.append("stateDescription = \(value)")
        }
        if modifiers.contains(where: { $0.name == "accessibilityTraversal" }) {
            context.imports.insert("androidx.compose.ui.semantics.isTraversalGroup")
            statements.append("isTraversalGroup = true")
        }
        if !actions.isEmpty {
            context.imports.insert("androidx.compose.ui.semantics.CustomAccessibilityAction")
            context.imports.insert("androidx.compose.ui.semantics.customActions")
            let rendered = try actions.map { action -> String in
                let label = try rememberAccessibilityText(action.label, named: "accessibilityAction",
                    isRoot: isRoot, into: &out, context: &context)
                let body = try renderAction(action.action, context: &context)
                return "CustomAccessibilityAction(label = \(label)) { \(body); true }"
            }
            statements.append("customActions = listOf(\(rendered.joined(separator: ", ")))")
        }
        guard !statements.isEmpty else { return "" }
        context.imports.insert("androidx.compose.ui.semantics.semantics")
        if statements.count == 1 { return ".semantics { \(statements[0]) }" }
        return ".semantics {\n" + statements.map { "\u{1}\($0)" }.joined(separator: "\n") + "\n}"
    }

    private func rememberAccessibilityText(_ expression: Expression, named name: String, isRoot: Bool,
                                           into out: inout KotlinWriter, context: inout Context) throws -> String {
        let key = name == "accessibilityAction" ? "accessibilityAction" : String(name.dropFirst("accessibility".count)).lowercased()
        let index = context.accessibilityTextValues[key] ?? 0
        context.accessibilityTextValues[key] = index + 1
        let identifier = isRoot ? "root\(key)\(index)" : "\(key)\(index)"
        let value = try renderExpression(expression, context: &context)
        guard isLocalized(expression) else { return value }
        context.imports.insert("androidx.compose.runtime.rememberUpdatedState")
        context.imports.insert("androidx.compose.runtime.getValue")
        out.line("val \(identifier) by rememberUpdatedState(\(value))")
        return identifier
    }

    private func isLocalized(_ expression: Expression) -> Bool {
        if case .localizedText = expression.value { return true }
        if case let .platformValue(alternatives) = expression.value { return isLocalized(alternatives.android) }
        return false
    }

    func prepareComposeAccessibilityTraversal(_ modifiers: [Modifier], children: [ViewNode]) throws -> AccessibilityTraversal? {
        guard let modifier = modifiers.first(where: { $0.name == "accessibilityTraversal" }),
              modifier.arguments.count == 1,
              case let .accessibilityTraversal(traversal) = modifier.arguments[0].value else { return nil }
        try validateTraversal(traversal, children: children, modifier: modifier)
        return traversal
    }

    func composeAccessibilityTraversalGroup(_ children: [ViewNode], modifiers: [Modifier]) throws -> Bool {
        guard modifiers.contains(where: { $0.name == "accessibilityTraversal" }) else { return false }
        let identifiers = children.flatMap { viewAccessibilityModifiers($0) }.filter {
            $0.name == "accessibilityIdentifier"
        }
        guard !identifiers.isEmpty else {
            throw Diagnostic(code: "RFACCESS003", message: "A Compose traversal group requires directly named accessible children.",
                suggestion: "Use a typed stack with direct children carrying accessibilityIdentifier; a nonsemantic container cannot group descendants.",
                location: modifiers.first(where: { $0.name == "accessibilityTraversal" })?.location)
        }
        return true
    }

    func validateTraversal(_ traversal: AccessibilityTraversal, children: [ViewNode], modifier: Modifier) throws {
        let identifiers = children.flatMap { child -> [String] in
            viewAccessibilityModifiers(child).filter { $0.name == "accessibilityIdentifier" }.compactMap {
                guard $0.arguments.count == 1, case let .stringLiteral(name) = $0.arguments[0].value else { return nil }
                return name
            }
        }
        guard identifiers.count == Set(identifiers).count,
              Set(identifiers) == Set(traversal.steps.map(\.name)),
              identifiers.count == traversal.steps.count else {
            throw Diagnostic(code: "RFACCESS003",
                message: "Traversal order must include every named direct child exactly once.",
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
    }

    func viewAccessibilityModifiers(_ node: ViewNode) -> [Modifier] {
        switch node {
        case let .stack(_, _, modifiers, _), let .text(_, modifiers, _), let .button(_, _, modifiers, _),
             let .layout(_, _, modifiers, _), let .scroll(_, _, modifiers, _), let .list(_, modifiers, _),
             let .image(_, modifiers, _), let .toggle(_, _, modifiers, _, _, _), let .textInput(_, _, modifiers, _),
             let .label(_, _, modifiers, _), let .divider(modifiers, _):
            return modifiers
        default: return []
        }
    }
}
