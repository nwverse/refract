import Testing
@testable import RefractFrontend
import RefractIR

@Test func frontendPreservesOnlyExplicitStackLayoutArguments() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Layout: View {
        var body: some View {
            VStack(alignment: .leading, spacing: .medium) {
                HStack { Text(verbatim: "Native defaults") }
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let root = try #require(unit.module.screens.first?.body)
    guard case let .layout(layout, children, _, _) = root else {
        Issue.record("Expected a typed vertical layout")
        return
    }
    #expect(layout.alignment == .leading)
    #expect(layout.spacing?.value == .layoutSpacing(.medium))
    guard case let .stack(axis, _, _, _) = children[0] else {
        Issue.record("Expected the legacy native-default horizontal stack")
        return
    }
    #expect(axis == .horizontal)
}

@Test(arguments: [
    "VStack(alignment: .top) { Text(verbatim: \"Bad\") }",
    "HStack(alignment: .leading) { Text(verbatim: \"Bad\") }",
    "ZStack(alignment: .leading) { Text(verbatim: \"Bad\") }",
    "VStack(spacing: .large) { Text(verbatim: \"Bad\") }",
    "VStack(spacing: DesignSpacing.large) { Text(verbatim: \"Bad\") }",
    "ZStack(spacing: .small) { Text(verbatim: \"Bad\") }",
])
func frontendRejectsUnsupportedLayoutArguments(expression: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Layout: View { var body: some View { \(expression) } }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFVIEW003"])
    #expect(unit.diagnostics.first?.suggestion != nil)
}
