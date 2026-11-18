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
            expression = Expression(.interpolatedString([.literal("value: "), .expression(expression)]),
                                    type: .string, location: location)
        }
    }
    return expression
}

@Test func deeplyNestedViewsCompareEveryFieldWithoutRecursiveEquality() {
    #expect(deepView() == deepView())
    #expect(deepView() != deepView(text: "different"))
    #expect(deepView() != deepView(differentLocationAt: 417))
}

@Test func deeplyNestedExpressionsCompareEveryFieldWithoutRecursiveEquality() {
    #expect(deepExpression() == deepExpression())
    #expect(deepExpression() != deepExpression(text: "different"))
    #expect(deepExpression() != deepExpression(differentLocationAt: 417))
}
