import Testing
@testable import RefractIR

private let deepEqualityDepth = 1_024

private func deepView(text: String = "leaf", differentLocationAt depth: Int? = nil) -> ViewNode {
    var node = ViewNode.text(Expression(.verbatimText(text)), modifiers: [], location: nil)
    for level in 0..<deepEqualityDepth {
        let location = SourceLocation(file: "Input.swift", line: level == depth ? 2 : 1, column: 1)
        if level.isMultiple(of: 2) {
            node = .platformView(PlatformAlternatives(ios: [node], android: [], harmonyOS: []),
                                 location: location)
        } else {
            node = .switchExpression(subject: Expression(.reference("root")), enumName: "Content", cases: [
                SwitchCase(name: "text", children: [node]),
            ], location: location)
        }
    }
    return node
}

private func deepExpression(text: String = "leaf", differentLocationAt depth: Int? = nil) -> Expression {
    var expression = Expression(.stringLiteral(text))
    for level in 0..<deepEqualityDepth {
        let location = SourceLocation(file: "Input.swift", line: level == depth ? 2 : 1, column: 1)
        if level.isMultiple(of: 2) {
            expression = Expression(.presence(expression), type: .bool, location: location)
        } else {
            expression = Expression(
                .interpolatedString([.literal("value: "), .expression(expression)]),
                type: .string, location: location)
        }
    }
    return expression
}

// These six deliberately deep values live until this short-lived test process exits.
// The bounded arena never grows with corpus seeds, production IR, or repeated assertions.
// In particular, no test-local value is the last owner of a recursive value chain.
private actor DeepViewTestArena {
    private var retained: [ViewNode] = []

    func compare(lhs: consuming ViewNode, rhs: consuming ViewNode) -> Bool {
        let result = lhs == rhs
        precondition(retained.count <= 4)
        retained.append(lhs)
        retained.append(rhs)
        return result
    }
}

private let deepViewTestArena = DeepViewTestArena()

@Suite(.serialized)
struct DeepViewEqualityTests {
    @Test func deeplyNestedViewsCompareEveryFieldWithoutRecursiveEquality() async {
        let equal = await deepViewTestArena.compare(lhs: deepView(), rhs: deepView())
        #expect(equal)

        let differentLeaf = await deepViewTestArena.compare(
            lhs: deepView(), rhs: deepView(text: "different"))
        #expect(!differentLeaf)

        let differentLocation = await deepViewTestArena.compare(
            lhs: deepView(), rhs: deepView(differentLocationAt: 417))
        #expect(!differentLocation)
    }

    @Test func ordinaryAndDeepExpressionsCompareEveryField() {
        let lhs = deepExpression()
        let rhs = deepExpression()
        #expect(lhs == rhs)
        #expect(deepExpression() != deepExpression(text: "different"))
        #expect(deepExpression() != deepExpression(differentLocationAt: 417))
    }
}
