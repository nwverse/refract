import RefractIR

/// Atomic resource resolution for CLI and golden generation, before any native output is emitted.
public enum LocalizationResourceValidator {
    public static func validate(module: Module, mapping: Mapping) throws {
        for expression in localizedExpressions(in: module) {
            guard case let .localizedText(text) = expression.value else { continue }
            _ = try mapping.stringCatalog(text, platform: .android, location: expression.location)
            _ = try mapping.stringCatalog(text, platform: .harmonyOS, location: expression.location)
        }
    }

    private static func localizedExpressions(in module: Module) -> [Expression] {
        func visit(_ node: ViewNode) -> [Expression] {
            switch node {
            case let .text(expression, modifiers, _):
                return [expression] + modifiers.flatMap(\.arguments)
            case let .markdown(document, _, modifiers, _):
                return document.blocks.flatMap { block -> [Expression] in
                    switch block {
                    case let .paragraph(paragraph):
                        func inlineExpressions(_ values: [MarkdownDocument.Inline]) -> [Expression] {
                            values.flatMap { value -> [Expression] in
                                switch value {
                                case let .text(expression): return [expression]
                                case let .strong(value), let .emphasis(value): return inlineExpressions([value])
                                case let .link(link): return [link.label]
                                case .inlineCode: return []
                                }
                            }
                        }
                        return inlineExpressions(paragraph.content)
                    case let .codeBlock(code):
                        return [Expression(.localizedText(code.accessibilityLabel), location: code.location)]
                    }
                } + modifiers.flatMap(\.arguments)
            case let .stack(_, children, modifiers, _):
                return children.flatMap(visit) + modifiers.flatMap(\.arguments)
            case let .button(label, _, modifiers, _):
                return visit(label) + modifiers.flatMap(\.arguments)
            case let .nativeModifier(child, operations, _):
                return visit(child) + operations.compactMap { modifier in
                    switch modifier.operation {
                    case let .testTag(value), let .contentDescription(value): value
                    case .retainCallback, .contentType, .textSelection, .dragPayload, .dropTarget: nil
                    }
                }
            case let .native(component, _):
                return component.arguments.compactMap(\.expression)
            case let .component(component, _):
                return component.arguments.compactMap(\.expression) + component.children.flatMap(visit)
                    + component.modifiers.flatMap(\.arguments)
            case .child:
                return []
            case let .platformView(alternatives, _):
                return (alternatives.android + alternatives.harmonyOS).flatMap(visit)
            case let .optionalBinding(subject, _, children, otherwise, _):
                return [subject] + children.flatMap(visit) + otherwise.flatMap(visit)
            case let .switchExpression(subject, _, cases, _):
                return [subject] + cases.flatMap { $0.children.flatMap(visit) }
            case let .conditional(branches, _):
                return branches.flatMap { branch in
                    (branch.condition.map { [$0] } ?? []) + branch.children.flatMap(visit)
                }
            case let .layout(layout, children, modifiers, _):
                return (layout.spacing.map { [$0] } ?? []) + children.flatMap(visit) + modifiers.flatMap(\.arguments)
            case let .scroll(_, child, modifiers, _):
                return visit(child) + modifiers.flatMap(\.arguments)
            case let .list(children, modifiers, _):
                return children.flatMap(visit) + modifiers.flatMap(\.arguments)
            case let .section(header, children, _):
                return (header.map { [$0] } ?? []) + children.flatMap(visit)
            case let .listItem(child, _):
                return visit(child)
            case let .forEach(items, _):
                return [items.collection] + visit(items.content)
            case let .messageBlocks(nested, _):
                return [nested.items.collection] + visit(nested.items.content)
            case let .image(_, modifiers, _):
                return modifiers.flatMap(\.arguments)
            case let .toggle(title, value, modifiers, nativeModifiers, _, _):
                return [title, value] + modifiers.flatMap(\.arguments) + nativeModifiers.compactMap {
                    switch $0.operation {
                    case let .testTag(value), let .contentDescription(value): value
                    case .retainCallback, .contentType, .textSelection, .dragPayload, .dropTarget: nil
                    }
                }
            case let .textInput(placeholder, value, modifiers, _):
                return (placeholder.map { [$0] } ?? []) + [value] + modifiers.flatMap(\.arguments)
            case let .secureInput(placeholder, value, reveal, modifiers, _):
                return (placeholder.map { [$0] } ?? []) + [value] + (reveal.map { [$0] } ?? [])
                    + modifiers.flatMap(\.arguments)
            case let .label(title, _, modifiers, _):
                return [title] + modifiers.flatMap(\.arguments)
            case let .divider(modifiers, _):
                return modifiers.flatMap(\.arguments)
            case let .navigationLink(title, _, _, _, _):
                return [title]
            case let .navigationStack(stack, _):
                return stack.content.flatMap(visit)
            case let .tabView(tabs, _):
                return tabs.destinations.map(\.title) + tabs.menuActions.map(\.title)
                    + (tabs.menuTitle.map { [$0] } ?? [])
            case .spacer:
                return []
            }
        }
        func expressions(in value: Expression) -> [Expression] {
            if case let .localizedText(text) = value.value {
                return [value] + text.arguments.flatMap(expressions)
            }
            if case let .platformValue(alternatives) = value.value {
                return [alternatives.android, alternatives.harmonyOS].flatMap(expressions)
            }
            return []
        }
        return module.screens.flatMap { visit($0.body) }.flatMap(expressions)
    }
}
