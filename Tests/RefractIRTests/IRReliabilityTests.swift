import Foundation
import Testing
@testable import RefractIR

private typealias IRExpression = RefractIR.Expression

/// Reproducible values only; no clocks, process entropy, filesystem or network input.
private struct FixedSeedGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

private struct IRCorpus {
    var random: FixedSeedGenerator

    init(seed: UInt64) { random = FixedSeedGenerator(seed: seed) }

    mutating func module() -> Module {
        let sample = view(depth: 0)
        let item = ItemType(name: "Item", identity: ItemProperty(name: "id", type: .string),
                            properties: [ItemProperty(name: "title", type: .string),
                                         ItemProperty(name: "enabled", type: .bool)], location: location())
        return Module(sourceFile: "Input.swift", screens: [
            Screen(name: "Generated", parameters: [
                ScreenParameter(name: "title", type: .string, isOptional: true, location: location()),
            ], states: [
                .state(name: "count", type: .int, initialValue: expression(), location: location()),
                .binding(name: "enabled", type: .bool, location: location()),
                .model(ModelReference(propertyName: "model", protocolName: "Model"), location: location()),
            ], body: sample, location: location()),
        ], nativeDeclarations: [NativeDeclaration(name: "Native", parameters: [
            NativeParameter(label: "title", type: .string, location: location()),
        ], location: location())], models: [ModelProtocol(name: "Model", properties: [
            ModelProperty(name: "items", type: .string,
                          collection: ModelCollection(itemType: "Item", key: "id", keyType: .string),
                          location: location()),
        ], actions: [ModelAction(name: "save", parameters: [
            ModelParameter(externalName: "title", localName: "value", type: .string),
        ], location: location())], location: location())], itemTypes: [item],
            enums: [EnumDeclaration(name: "Content", cases: ["text"], payloadTypes: ["text": .string],
                                    location: location())])
    }

    private mutating func view(depth: Int) -> ViewNode {
        let leafCount = 12
        // Navigation and message-block cases join the existing selector without pre-empting it.
        let selection = Int.random(in: 0..<(depth < 3 ? 29 : leafCount + 3), using: &random)
        switch selection {
        case 24:
            return .navigationLink(title: expression(), pathName: "path", enumName: "Route",
                                   destination: "detail", location: location())
        case 25:
            return .navigationStack(NavigationStackNode(pathName: "path", enumName: "Route",
                content: children(depth: depth), destinations: [
                    NavigationDestination(caseName: "detail", viewName: "Detail"),
                ]), location: location())
        case 26, 27:
            return .tabView(TabViewNode(selectionName: "tab", enumName: "Tab", destinations: [
                TabDestination(caseName: "home", viewName: "Home", title: expression(), symbol: "house"),
            ]), location: location())
        case 28:
            let inline = MarkdownDocument.Inline.strong(.link(MarkdownDocument.Link(
                label: expression(),
                destination: .init(scheme: "https", host: "example.com", path: "/docs"))))
            return .markdown(MarkdownDocument(version: 1, blocks: [
                .paragraph(.init(id: "answer.summary", content: [inline, .text(expression())], location: location())),
                .codeBlock(.init(id: "answer.example", language: .swift,
                    accessibilityLabel: LocalizedText(key: "conversation.code.label", arguments: [expression()]),
                    code: "let answer = 42", location: location())),
            ]), linkAction: MarkdownLinkAction(model: "model", method: "openLink", argumentLabel: "url"),
               modifiers: modifiers(), location: location())
        default:
            break
        }
        switch selection {
        case 0: return .stack(axis: axis(), children: children(depth: depth), modifiers: modifiers(), location: location())
        case 1: return .text(expression(), modifiers: modifiers(), location: location())
        case 2: return .button(label: .text(expression(), modifiers: [], location: location()), action: action(),
                               modifiers: modifiers(), location: location())
        case 3: return .native(NativeComponent(name: "Native", arguments: [
            NativeArgument(label: "title", expression: expression(), type: .string, location: location()),
        ]), location: location())
        case 4: return .nativeModifier(child: .text(expression(), modifiers: [], location: location()),
                                       operations: nativeOperations(), location: location())
        case 5: return .component(ComponentReference(name: "Card", arguments: [], children: children(depth: depth),
                                                     modifiers: modifiers()), location: location())
        case 6: return .child(ChildView(name: "Child", arguments: [
            ChildView.Argument(label: "row", expression: "row"),
        ], models: [ChildView.Argument(label: "model", expression: "model")],
            item: ChildView.Argument(label: "row", expression: "row"), contentType: "setting"), location: location())
        case 7: return .platformView(PlatformAlternatives(ios: children(depth: depth), android: children(depth: depth),
                                                         harmonyOS: children(depth: depth)), location: location())
        case 8: return .conditional(conditions: [
            ViewNode.ConditionBranch(condition: expression(), children: children(depth: depth)),
            ViewNode.ConditionBranch(condition: nil, children: children(depth: depth)),
        ], location: location())
        case 9: return .optionalBinding(subject: expression(), binding: "title", children: children(depth: depth),
                                       otherwise: children(depth: depth), location: location())
        case 10: return .switchExpression(subject: expression(), enumName: "Content", cases: [
            SwitchCase(name: "text", binding: "value", children: children(depth: depth)),
        ], location: location())
        case 11: return .layout(LayoutContainer(axis: axis(), alignment: alignment(), spacing: expression()),
                                children: children(depth: depth), modifiers: modifiers(), location: location())
        case 12: return .scroll(axis: axis(), child: .text(expression(), modifiers: [], location: location()),
                                modifiers: modifiers(), location: location())
        case 13: return .list(children: children(depth: depth), modifiers: modifiers(), location: location())
        case 14: return .section(header: expression(), children: children(depth: depth), location: location())
        case 15: return .listItem(child: .text(expression(), modifiers: [], location: location()), location: location())
        case 16: return .forEach(ListItems(collection: expression(), itemName: "row", itemType: "Item", key: "id",
                                          keyType: .string, content: .text(expression(), modifiers: [], location: location()),
                                          contentType: "setting", location: location()), location: location())
        case 17: return .image(source: ImageSource(kind: .system, name: "gear", location: location()),
                               modifiers: modifiers(), location: location())
        case 18: return .toggle(title: expression(), value: expression(), modifiers: modifiers(),
                                nativeModifiers: nativeOperations(), labelsHidden: Bool.random(using: &random), location: location())
        case 19: return .textInput(placeholder: expression(), value: expression(), modifiers: modifiers(), location: location())
        case 22: return .secureInput(placeholder: expression(), value: expression(), reveal: nil,
                                     modifiers: modifiers(), location: location())
        case 23:
            let items = ListItems(collection: Expression(.reference("message.blocks")), itemName: "block",
                itemType: "ChatBlock", keyType: .string,
                content: .text(expression(), modifiers: [], location: location()))
            return .messageBlocks(NestedListItems(items, parent: "message",
                message: .init(label: "message", expression: "message"),
                block: .init(label: "block", expression: "block")), location: location())
        case 20: return .label(title: expression(), image: ImageSource(kind: .application, name: "logo", location: location()),
                               modifiers: modifiers(), location: location())
        case 21: return Bool.random(using: &random) ? .divider(modifiers: modifiers(), location: location()) : .spacer(location: location())
        default: preconditionFailure("Bounded IR case selection is exhaustive.")
        }
    }

    private mutating func children(depth: Int) -> [ViewNode] {
        (0..<Int.random(in: 0...2, using: &random)).map { _ in view(depth: depth + 1) }
    }

    private mutating func axis() -> ViewNode.StackAxis {
        [.vertical, .horizontal, .depth].randomElement(using: &random)!
    }

    private mutating func alignment() -> LayoutAlignment? {
        [nil, .center, .leading, .trailing, .top, .bottom, .topLeading, .bottomTrailing].randomElement(using: &random)!
    }

    private mutating func expression() -> RefractIR.Expression {
        let value: IRExpression.Value
        switch Int.random(in: 0..<19, using: &random) {
        case 0: value = .stringLiteral("value\(Int.random(in: 0...100, using: &random))")
        case 1: value = .verbatimText("literal")
        case 2: value = .stringKey("settings.title")
        case 3: value = .localizedText(LocalizedText(key: "settings.title", arguments: [IRExpression(.reference("title"))]))
        case 4: value = .boolLiteral(Bool.random(using: &random))
        case 5: value = .numberLiteral(String(Int.random(in: 0...100, using: &random)))
        case 6: value = .layoutSpacing(Bool.random(using: &random) ? .small : .medium)
        case 7: value = .reference("model.title")
        case 8: value = .binding("enabled")
        case 9: value = .valueProperty(.itemBinding(ItemBinding(model: "model", item: "row", property: "enabled", key: "id", action: "setEnabled")))
        case 10: let segments: [StringInterpolationSegment] = [.literal("Count: "), .expression(IRExpression(.reference("count"), type: .int))]
            value = .interpolatedString(segments)
        case 11: value = .interactionColor(InteractionColorValue(token: "DesignColors.action",
            enabled: IRExpression(.valueProperty(.binding("enabled")), type: .bool),
            pressed: IRExpression(.boolLiteral(false), type: .bool),
            focused: IRExpression(.boolLiteral(true), type: .bool)))
        case 12: value = .platformValue(PlatformAlternatives(
            ios: IRExpression(.stringLiteral("iOS")), android: IRExpression(.stringLiteral("Android")),
            harmonyOS: IRExpression(.stringLiteral("HarmonyOS"))))
        case 13: value = .formField(form: "draft", field: "email")
        case 14: value = .presence(IRExpression(.reference("model.error")))
        case 15: value = .imageResource("app_logo")
        case 16: value = .rawAssetResource("privacy_policy")
        case 17: value = .fontAsset(name: "app_body", size: "16")
        default:
            value = .formValid(FormDeclaration(name: "draft", fields: [
                FormField(name: "email", initialValue: IRExpression(.stringLiteral("")), rules: [.nonEmpty]),
            ]))
        }
        return IRExpression(value, type: [nil, .string, .bool, .double, .int].randomElement(using: &random)!, location: location())
    }

    private mutating func modifiers() -> [Modifier] {
        (0..<Int.random(in: 0...2, using: &random)).map { _ in
            Modifier(name: "padding", arguments: [expression()], argumentLabels: [[nil], ["all"]].randomElement(using: &random)!,
                     location: location())
        }
    }

    private mutating func nativeOperations() -> [NativeModifier] {
        let operation: NativeModifier.Operation
        switch Int.random(in: 0..<4, using: &random) {
        case 0: operation = .testTag(expression())
        case 1: operation = .contentDescription(expression())
        case 2: operation = .retainCallback(identity: "save")
        default: operation = .contentType("setting")
        }
        return [NativeModifier(operation: operation, location: location())]
    }

    private mutating func action() -> StateAction {
        switch Int.random(in: 0..<4, using: &random) {
        case 0: return .assign(.state("enabled"), expression())
        case 1: return .increment(.binding("count"), expression())
        case 2: return .assign(.binding("enabled"), expression())
        default: return .modelMethod(model: "model", name: "save", arguments: [
            ActionArgument(label: "title", value: expression()),
        ])
        }
    }

    private mutating func location() -> RefractIR.SourceLocation? {
        return RefractIR.SourceLocation(file: "Input.swift", line: Int.random(in: 1...200, using: &random),
                       column: Int.random(in: 1...80, using: &random))
    }
}

@Suite("Fixed-seed typed IR differential")
struct IRReliabilityTests {
    @Test func codingPreservesEveryPublicIRCase() throws {
        // All 29 public ViewNode cases and all 19 Expression.Value cases must actually occur.
        // A triple-branch platform node multiplies its subtree on each platform. The strictest
        // three-level nesting produces 397 nodes, so every generated input has a checked bound.
        var seenViews = Set<String>()
        var seenExpressions = Set<String>()
        for seed in 0..<UInt64(128) {
            var corpus = IRCorpus(seed: seed)
            let module = corpus.module()
            #expect(viewCount(in: module.screens[0].body) <= 397)
            collectCases(in: module.screens[0].body, views: &seenViews, expressions: &seenExpressions)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let encoded = try encoder.encode(module)
            let decoded = try JSONDecoder().decode(Module.self, from: encoded)
            #expect(decoded == module, "IR coding mismatch at fixed seed \(seed)")
            #expect(try encoder.encode(decoded) == encoded, "IR re-encoding differs at fixed seed \(seed)")
            var replay = IRCorpus(seed: seed)
            #expect(replay.module() == module, "The test generator itself is not reproducible at seed \(seed)")
        }
        #expect(seenViews.count == 29, "Visited view cases: \(seenViews.sorted())")
        #expect(seenExpressions.count == 19, "Visited expression cases: \(seenExpressions.sorted())")
    }

    private func collectCases(in node: ViewNode, views: inout Set<String>, expressions: inout Set<String>) {
        views.insert(String(describing: node).split(separator: "(").first.map(String.init) ?? "")
        switch node {
        case let .text(value, modifiers, _):
            collectExpression(value, into: &expressions)
            collect(modifiers, into: &expressions)
        case let .markdown(document, _, modifiers, _):
            collect(modifiers, into: &expressions)
            for block in document.blocks {
                switch block {
                case let .paragraph(paragraph):
                    for inline in paragraph.content { collectMarkdown(inline, into: &expressions) }
                case let .codeBlock(code):
                    for argument in code.accessibilityLabel.arguments {
                        collectExpression(argument, into: &expressions)
                    }
                }
            }
        case let .button(_, action, modifiers, _):
            collect(action, into: &expressions)
            collect(modifiers, into: &expressions)
        case let .navigationLink(title, _, _, _, _):
            collectExpression(title, into: &expressions)
        case let .section(header, _, _):
            if let header { collectExpression(header, into: &expressions) }
        case .navigationStack:
            break
        case let .tabView(tabs, _):
            for destination in tabs.destinations { collectExpression(destination.title, into: &expressions) }
            if let title = tabs.menuTitle { collectExpression(title, into: &expressions) }
            for action in tabs.menuActions {
                collectExpression(action.title, into: &expressions)
                collect(action.action, into: &expressions)
            }
        case let .native(component, _):
            collect(component.arguments, into: &expressions)
        case let .nativeModifier(_, operations, _):
            for operation in operations { collect(operation.operation, into: &expressions) }
        case let .component(component, _):
            collect(component.arguments, into: &expressions)
            collect(component.modifiers, into: &expressions)
        case let .conditional(branches, _):
            for branch in branches {
                if let condition = branch.condition { collectExpression(condition, into: &expressions) }
            }
        case let .optionalBinding(subject, _, _, _, _):
            collectExpression(subject, into: &expressions)
        case let .switchExpression(subject, _, _, _):
            collectExpression(subject, into: &expressions)
        case let .layout(layout, _, modifiers, _):
            if let spacing = layout.spacing { collectExpression(spacing, into: &expressions) }
            collect(modifiers, into: &expressions)
        case let .stack(_, _, modifiers, _), let .scroll(_, _, modifiers, _),
             let .list(_, modifiers, _), let .image(_, modifiers, _), let .divider(modifiers, _):
            collect(modifiers, into: &expressions)
        case let .forEach(items, _):
            collectExpression(items.collection, into: &expressions)
        case let .messageBlocks(nested, _):
            collectExpression(nested.items.collection, into: &expressions)
        case let .toggle(title, value, modifiers, nativeModifiers, _, _):
            for value in [title, value] { collectExpression(value, into: &expressions) }
            collect(modifiers, into: &expressions)
            for operation in nativeModifiers { collect(operation.operation, into: &expressions) }
        case let .textInput(placeholder, value, modifiers, _):
            if let placeholder { collectExpression(placeholder, into: &expressions) }
            collectExpression(value, into: &expressions)
            collect(modifiers, into: &expressions)
        case let .secureInput(placeholder, value, reveal, modifiers, _):
            for value in [placeholder, reveal].compactMap({ $0 }) + [value] {
                collectExpression(value, into: &expressions)
            }
            collect(modifiers, into: &expressions)
        case let .label(title, _, modifiers, _):
            collectExpression(title, into: &expressions)
            collect(modifiers, into: &expressions)
        case .child, .platformView, .listItem, .spacer:
            break
        }
        for child in node.children { collectCases(in: child, views: &views, expressions: &expressions) }
    }

    private func collectExpression(_ expression: IRExpression, into expressions: inout Set<String>) {
        expressions.insert(String(describing: expression.value).split(separator: "(").first.map(String.init) ?? "")
        switch expression.value {
        case let .interactionColor(value):
            for state in [value.enabled, value.pressed, value.focused] { collectExpression(state, into: &expressions) }
        case let .platformValue(alternatives):
            for branch in [alternatives.ios, alternatives.android, alternatives.harmonyOS] {
                collectExpression(branch, into: &expressions)
            }
        case let .presence(subject):
            collectExpression(subject, into: &expressions)
        case let .formValid(form):
            for field in form.fields { collectExpression(field.initialValue, into: &expressions) }
        default:
            break
        }
    }

    private func collectMarkdown(_ inline: MarkdownDocument.Inline, into expressions: inout Set<String>) {
        switch inline {
        case let .text(value): collectExpression(value, into: &expressions)
        case let .strong(content), let .emphasis(content): collectMarkdown(content, into: &expressions)
        case let .link(link): collectExpression(link.label, into: &expressions)
        case .inlineCode: break
        }
    }

    private func collect(_ modifiers: [Modifier], into expressions: inout Set<String>) {
        for modifier in modifiers {
            for argument in modifier.arguments { collectExpression(argument, into: &expressions) }
        }
    }

    private func collect(_ arguments: [NativeArgument], into expressions: inout Set<String>) {
        for argument in arguments {
            if let expression = argument.expression { collectExpression(expression, into: &expressions) }
            collect(argument.action, into: &expressions)
        }
    }

    private func collect(_ action: StateAction?, into expressions: inout Set<String>) {
        guard let action else { return }
        switch action {
        case let .assign(_, value), let .increment(_, value):
            collectExpression(value, into: &expressions)
        case let .modelMethod(_, _, arguments):
            for argument in arguments { collectExpression(argument.value, into: &expressions) }
        case let .submit(submit):
            if let form = submit.declaration {
                for field in form.fields { collectExpression(field.initialValue, into: &expressions) }
            }
        }
    }

    private func collect(_ operation: NativeModifier.Operation, into expressions: inout Set<String>) {
        switch operation {
        case let .testTag(value), let .contentDescription(value), let .dragPayload(_, value):
            collectExpression(value, into: &expressions)
        case let .textSelection(start, end, _):
            for value in [start, end] { collectExpression(value, into: &expressions) }
        case .retainCallback, .contentType, .dropTarget:
            break
        }
    }

    private func viewCount(in node: ViewNode) -> Int {
        1 + node.children.reduce(0) { $0 + viewCount(in: $1) }
    }

    @Test(arguments: [
        Data(), Data("{".utf8), Data("null".utf8), Data("[]".utf8),
        Data("{\"sourceFile\":\"Input.swift\",\"screens\":null}".utf8),
        Data("{\"sourceFile\":\"Input.swift\",\"screens\":[{\"body\":{\"unknown\":{}}]}".utf8),
        Data("{\"sourceFile\":\"Input.swift\",\"screens\":[],\"itemTypes\":{}}".utf8),
    ])
    func malformedIRIsRejectedRatherThanDefaulted(data: Data) {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Module.self, from: data)
        }
    }
}
