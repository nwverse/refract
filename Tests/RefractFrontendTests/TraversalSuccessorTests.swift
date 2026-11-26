import Testing
@testable import RefractFrontend
@testable import RefractCompose
@testable import RefractArkUI
import RefractIR

private let traversalBranchSource = SourceFile(path: "Input.swift", contents: """
struct Ordered: View {
    var body: some View {
        refractView(
            ios: { Text(verbatim: "Control") },
            android: {
                VStack {
                    Button("accessibility.sync.title") { }.accessibilityIdentifier("first")
                    Button("accessibility.sync.now") { }.accessibilityIdentifier("second")
                    Button("accessibility.sync.details") { }.accessibilityIdentifier("third")
                }
                .accessibilityTraversal([
                    .accessibility("first"),
                    .accessibility("second", after: "first"),
                    .accessibility("third", after: "first"),
                ])
            },
            harmonyOS: { Text(verbatim: "Control") }
        )
    }
}
""")

private func accessibilityTraversalFixture() -> (modifier: Modifier, children: [ViewNode]) {
    let steps = [
        AccessibilityTraversal.Step(name: "first"),
        AccessibilityTraversal.Step(name: "second", after: "first"),
        AccessibilityTraversal.Step(name: "third", after: "first"),
    ]
    let children = ["first", "second", "third"].map { name in
        ViewNode.button(
            label: .text(Expression(.verbatimText(name)), modifiers: [], location: nil), action: nil,
            modifiers: [Modifier(name: "accessibilityIdentifier", arguments: [Expression(.stringLiteral(name))])],
            location: nil)
    }
    return (Modifier(name: "accessibilityTraversal", arguments: [Expression(.accessibilityTraversal(
        AccessibilityTraversal(steps: steps)))]), children)
}

@Test func frontendRejectsMultipleSuccessors() {
    let unit = Frontend.parse(traversalBranchSource)
    #expect(unit.hasErrors)
    #expect(unit.module.screens.isEmpty)
    #expect(unit.diagnostics.contains { $0.code == "RFACCESS003" })
}

@Test func composeTraversalRejectsMultipleSuccessors() {
    let fixture = accessibilityTraversalFixture()
    #expect(throws: Diagnostic.self) {
        try ComposeBackend().prepareComposeAccessibilityTraversal([fixture.modifier], children: fixture.children)
    }
}

@Test func arkUITraversalRejectsMultipleSuccessors() {
    let fixture = accessibilityTraversalFixture()
    #expect(throws: Diagnostic.self) {
        try ArkModifiers.validateAccessibilityTraversal([fixture.modifier], children: fixture.children, mapping: .empty)
    }
}
