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
        let selection = Int.random(in: 0..<(depth < 3 ? 22 : leafCount), using: &random)
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
        switch Int.random(in: 0..<12, using: &random) {
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
        default: value = .platformValue(PlatformAlternatives(
            ios: IRExpression(.stringLiteral("iOS")), android: IRExpression(.stringLiteral("Android")),
            harmonyOS: IRExpression(.stringLiteral("HarmonyOS"))))
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
        // All 23 public ViewNode cases and all 12 Expression.Value cases must actually occur.
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
            // Synthesized equality recursively descends every nested view on a
            // cooperative Testing thread. Byte equality is the stronger coding
            // assertion and does not consume that bounded thread's stack.
            #expect(try encoder.encode(decoded) == encoded, "IR re-encoding differs at fixed seed \(seed)")
            var replay = IRCorpus(seed: seed)
            #expect(try encoder.encode(replay.module()) == encoded,
                    "The test generator itself is not reproducible at seed \(seed)")
        }
        #expect(seenViews.count == 23, "Visited view cases: \(seenViews.sorted())")
        #expect(seenExpressions.count == 12, "Visited expression cases: \(seenExpressions.sorted())")
    }

    private func collectCases(in node: ViewNode, views: inout Set<String>, expressions: inout Set<String>) {
        views.insert(String(describing: node).split(separator: "(").first.map(String.init) ?? "")
        if case let .text(expression, _, _) = node {
            expressions.insert(String(describing: expression.value).split(separator: "(").first.map(String.init) ?? "")
        }
        for child in node.children { collectCases(in: child, views: &views, expressions: &expressions) }
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
