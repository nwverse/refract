import RefractIR
import SwiftSyntax

/// Native accessibility text and actions keep SwiftUI's ordinary Text syntax.
/// Only source-order descriptions are accepted; arbitrary visual reordering is not guessed.
extension Builder {
    private static let accessibilityTextModifiers: Set<String> = [
        "accessibilityLabel", "accessibilityHint", "accessibilityValue",
    ]

    private func hasSupportedAccessibilityReceiver(_ node: ViewNode) -> Bool {
        if case .component = node { return false }
        return true
    }

    func accessibilityModifier(_ call: FunctionCallExprSyntax, name: String,
                               on node: ViewNode) -> ViewNode? {
        if Self.accessibilityTextModifiers.contains(name) {
            return accessibilityTextModifier(call, name: name, on: node)
        }
        if name == "accessibilityAction" {
            return accessibilityAction(call, on: node)
        }
        if name == "accessibilityTraversal" {
            return accessibilityTraversal(call, on: node)
        }
        return nil
    }

    private func accessibilityTextModifier(_ call: FunctionCallExprSyntax, name: String,
                                           on node: ViewNode) -> ViewNode? {
        if !hasSupportedAccessibilityReceiver(node) {
            error("RFACCESS004", "Native accessibility modifiers require a concrete supported view, not a mapped component.",
                  "Apply the modifier to a native control inside the component, or declare an accessible native boundary.", at: call)
            return nil
        }
        guard call.arguments.count == 1, call.arguments.first?.label == nil,
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              let argument = call.arguments.first?.expression else {
            error("RFACCESS001", "`\(name)` takes exactly one ordinary SwiftUI Text argument.",
                  "Use `.\(name)(Text(\"accessibility.key\"))`.", at: call)
            return nil
        }
        let value: Expression?
        if let textCall = argument.as(FunctionCallExprSyntax.self),
           textCall.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Text" {
            var parser = LocalizationFrontend(file: file, converter: converter, scalar: scalar,
                typedScalar: modelTypedProperty, stateText: stateText,
                enumInputNames: Set(parameters.compactMap { $0.enumName == nil ? nil : $0.name }))
            value = parser.text(textCall, arguments: textCall.arguments)
            diagnostics.append(contentsOf: parser.diagnostics)
            if value != nil, case .verbatimText = value!.value {
                error("RFACCESS001", "Accessibility text must use a localized resource, not verbatim text.",
                      "Use a canonical `Text(\"accessibility.key\")` declared in both string catalogs.", at: argument)
                return nil
            }
        } else if name == "accessibilityLabel" {
            // Preserve the existing model-backed String overload from the dynamic-type contract.
            if let typed = modelTypedProperty(argument) {
                value = Expression(typed.expression.value, type: typed.type, location: typed.expression.location)
            } else {
                value = nil
            }
        } else {
            value = nil
        }
        guard let value else {
            if name != "accessibilityLabel" || !diagnostics.contains(where: { $0.location == location(of: call) }) {
                error("RFACCESS001", "`\(name)` requires localized Text or a statically typed String label.",
                      "Use `Text(\"accessibility.key\")`; a label may also read a declared model String.", at: call)
            }
            return nil
        }
        guard value.type == .string else {
            error("RFACCESS001", "Accessibility text must have a statically known String type.",
                  "Use localized Text or a declared String model property.", at: argument)
            return nil
        }
        guard !accessibilityModifiers(node).contains(where: { $0.name == name }) else {
            error("RFACCESS004", "`\(name)` can be declared only once per receiver.",
                  "Combine the intended text in one localized value rather than relying on platform override order.", at: call)
            return nil
        }
        return modifier(name, arguments: [value], argumentLabels: [nil], on: node, at: call)
    }

    private func accessibilityAction(_ call: FunctionCallExprSyntax, on node: ViewNode) -> ViewNode? {
        guard hasSupportedAccessibilityReceiver(node) else {
            error("RFACCESS004", "A custom accessibility action cannot be attached to a mapped component without a native semantics contract.",
                  "Apply the action to a concrete control inside that component.", at: call)
            return nil
        }
        guard call.arguments.map(\.label?.text) == ["named"],
              let label = call.arguments.first?.expression,
              let textCall = label.as(FunctionCallExprSyntax.self),
              textCall.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Text",
              let closure = call.trailingClosure, call.additionalTrailingClosures.isEmpty else {
            error("RFACCESS002", "A custom accessibility action requires a localized name and one typed synchronous action.",
                  "Use `.accessibilityAction(named: Text(\"accessibility.action\")) { model.action() }`.", at: call)
            return nil
        }
        var parser = LocalizationFrontend(file: file, converter: converter, scalar: scalar,
            typedScalar: modelTypedProperty, stateText: stateText,
            enumInputNames: Set(parameters.compactMap { $0.enumName == nil ? nil : $0.name }))
        guard let name = parser.text(textCall, arguments: textCall.arguments),
              case .localizedText = name.value else {
            diagnostics.append(contentsOf: parser.diagnostics)
            error("RFACCESS002", "An accessibility action name must be a static localized resource key.",
                  "Use `Text(\"accessibility.action\")`, not a verbatim or dynamically constructed action name.", at: label)
            return nil
        }
        diagnostics.append(contentsOf: parser.diagnostics)
        guard let action = localStateAction(closure) else {
            error("RFACCESS002", "The accessibility action has no typed synchronous implementation.",
                  "Call a declared model action or assign a supported local state value.", at: closure)
            return nil
        }
        let value = AccessibilityCustomAction(label: name, action: action)
        let expression = Expression(.accessibilityAction(value), location: location(of: call))
        guard !accessibilityModifiers(node).contains(where: { $0.name == "accessibilityAction" }) else {
            error("RFACCESS002", "This bounded slice accepts one custom accessibility action per receiver.",
                  "Expose one action with an ordinary visible alternative; repeated action modifiers are not emitted as an ambiguous list.", at: call)
            return nil
        }
        return modifier("accessibilityAction", arguments: [
            expression,
        ], argumentLabels: ["named"], on: node, at: call)
    }

    private func accessibilityTraversal(_ call: FunctionCallExprSyntax, on node: ViewNode) -> ViewNode? {
        guard hasSupportedAccessibilityReceiver(node) else {
            error("RFACCESS004", "Traversal requires a supported stack, not a mapped component.",
                  "Apply traversal to the native container inside the component.", at: call)
            return nil
        }
        switch node {
        case .stack, .layout: break
        default:
            error("RFACCESS003", "Traversal order belongs on a stack with directly named actionable children.",
                  "Apply `.accessibilityTraversal([...])` to VStack, HStack or a supported typed stack.", at: call)
            return nil
        }
        guard accessibilityPlatform == .android || accessibilityPlatform == .harmonyOS else {
            error("RFACCESS003", "accessibilityTraversal is a bounded Android/HarmonyOS source form.",
                  "Use ordinary `.accessibilitySortPriority` inside the explicit iOS refractView branch.", at: call)
            return nil
        }
        var identifiers: [String] = []
        for child in node.children(for: accessibilityPlatform ?? .android) {
            switch child {
            case .button, .toggle, .textInput, .image:
                identifiers.append(contentsOf: accessibilityNames(accessibilityModifiers(child)))
            default:
                if !accessibilityNames(accessibilityModifiers(child)).isEmpty {
                    diagnostics.append(Diagnostic(code: "RFACCESS003",
                        message: "Traversal identifiers belong on independently actionable or image children.",
                        suggestion: "Put `.accessibilityIdentifier` on a Button, Toggle, TextField or Image, not decorative Text or an unmerged container.",
                        location: child.sourceLocation))
                    return nil
                }
            }
        }
        let children = Set(identifiers)
        let hasInvalidIdentifier = identifiers.count != children.count
        guard !children.isEmpty else {
            error("RFACCESS003", "Traversal order belongs on a container with named direct children.",
                  "Apply `.accessibilityTraversal([...])` to a supported stack.", at: call)
            return nil
        }
        if identifiers.count != children.count {
            error("RFACCESS003", "Every traversal identifier must be unique within its direct parent.",
                  "Give each actionable direct child a distinct accessibilityIdentifier.", at: call)
            return nil
        }
        guard call.arguments.count == 1, call.arguments.first?.label == nil,
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              let array = call.arguments.first?.expression.as(ArrayExprSyntax.self) else {
            error("RFACCESS003", "Traversal order requires one array of direct-child `.accessibility(...)` descriptors.",
                  "Use `.accessibilityTraversal([.accessibility(\"second\", after: \"first\")])`.", at: call)
            return nil
        }
        var steps: [AccessibilityTraversal.Step] = []
        var names: Set<String> = []
        for element in array.elements {
            guard let descriptor = element.expression.as(FunctionCallExprSyntax.self),
                  let member = descriptor.calledExpression.as(MemberAccessExprSyntax.self),
                  member.base == nil, member.declName.baseName.text == "accessibility",
                  descriptor.trailingClosure == nil,
                  (descriptor.arguments.map(\.label?.text) == [nil]
                   || descriptor.arguments.map(\.label?.text) == [nil, "after"]),
                  let identifier = stringLiteral(descriptor.arguments.first!.expression),
                  !identifier.isEmpty, identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
                  children.contains(identifier) else {
                error("RFACCESS003", "Each traversal entry must name a direct child with `.accessibility(\"name\")`.",
                      "Use a literal identifier declared directly on a child of this container.", at: element.expression)
                return nil
            }
            guard names.insert(identifier).inserted else {
                error("RFACCESS003", "A direct child can appear only once in its parent's traversal order.",
                      "Keep a unique name for each ordered child.", at: element.expression)
                return nil
            }
            var after: String?
            if descriptor.arguments.count == 2 {
                let arguments = Array(descriptor.arguments)
                guard let previous = stringLiteral(arguments[1].expression),
                      names.contains(previous) else {
                    error("RFACCESS003", "`after` must name an earlier entry in the same traversal sequence.",
                          "Declare the predecessor before the dependent child; cycles cannot be represented.", at: arguments[1].expression)
                    return nil
                }
                after = previous
            }
            steps.append(AccessibilityTraversal.Step(name: identifier, after: after))
        }
        guard Set(names) == children, names.count == children.count, identifiers.count == children.count else {
            error("RFACCESS003", "Traversal order must include every named direct child exactly once, with no duplicate identifiers.",
                  "Give each direct child a unique `.accessibilityIdentifier(...)` and include it in this sequence.", at: call)
            return nil
        }
        let value = AccessibilityTraversal(steps: steps)
        return modifier("accessibilityTraversal", arguments: [
            Expression(.accessibilityTraversal(value), location: location(of: call)),
        ], on: node, at: call)
    }

    private func accessibilityModifiers(_ node: ViewNode) -> [Modifier] {
        switch node {
            case let .stack(_, _, modifiers, _), let .text(_, modifiers, _), let .button(_, _, modifiers, _),
                 let .layout(_, _, modifiers, _), let .scroll(_, _, modifiers, _), let .list(_, modifiers, _),
                 let .image(_, modifiers, _), let .toggle(_, _, modifiers, _, _, _), let .textInput(_, _, modifiers, _),
                 let .label(_, _, modifiers, _), let .divider(modifiers, _):
                return modifiers
            default: return []
        }
    }

    private func accessibilityNames(_ modifiers: [Modifier]) -> [String] {
        modifiers.filter { $0.name == "accessibilityIdentifier" }.compactMap {
            guard $0.arguments.count == 1, case let .stringLiteral(value) = $0.arguments[0].value else { return nil }
            return value
        }
    }
}

extension Builder {
    /// iOS-native ordering is valid SwiftUI but is intentionally not part of generated Android/ArkUI IR.
    func accessibilitySortPriority(_ call: FunctionCallExprSyntax, on node: ViewNode) -> ViewNode? {
        guard call.arguments.count == 1, call.arguments.first?.label == nil,
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              let priority = Double(call.arguments.first!.expression.trimmedDescription), priority.isFinite else {
            error("RFACCESS003", "An iOS accessibility sort priority must be one finite numeric literal.",
                  "Use a negative priority to place this element after the default-priority siblings.", at: call)
            return nil
        }
        guard accessibilityPlatform == .ios else {
            error("RFACCESS003", "accessibilitySortPriority is iOS-only and cannot define Android/HarmonyOS traversal.",
                  "Keep it inside the explicit iOS refractView branch and use bounded accessibilityTraversal on native branches.", at: call)
            return nil
        }
        return node
    }

    func accessibilityIdentifier(_ call: FunctionCallExprSyntax, on node: ViewNode) -> ViewNode? {
        guard hasSupportedAccessibilityReceiver(node) else {
            error("RFACCESS004", "An accessibility identifier cannot be attached to a mapped component without a native semantics contract.",
                  "Apply the identifier to a concrete child inside that component.", at: call)
            return nil
        }
        guard call.arguments.count == 1, call.arguments.first?.label == nil,
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              let value = stringLiteral(call.arguments.first!.expression), !value.isEmpty,
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else {
            error("RFACCESS003", "An accessibility identifier is a nonempty ASCII letter, digit or underscore string.",
                  "Use `.accessibilityIdentifier(\"sync_now\")` on a direct container child.", at: call)
            return nil
        }
        return modifier("accessibilityIdentifier", arguments: [
            Expression(.stringLiteral(value), type: .string, location: location(of: call)),
        ], on: node, at: call)
    }
}
