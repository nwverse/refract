import Testing
@testable import RefractFrontend
import RefractIR
import RefractGolden
import RefractMapping

@Test func builtinModifierParserPreservesLabelsAndTargetValues() throws {
    let source = SourceFile(path: "Input.swift", contents: """
    struct ModifierForms: View {
        var body: some View {
            Text(verbatim: "Dimensions")
                .padding(.horizontal, 16)
                .frame(width: 120, height: 44)
                .opacity(refractValue(ios: 0.5, android: 0.6, harmonyOS: 0.7))
        }
    }
    """)
    let unit = Frontend.parse(source)
    #expect(unit.diagnostics.isEmpty)
    guard case let .text(_, modifiers, _)? = unit.module.screens.first?.body else {
        Issue.record("Expected a modified Text")
        return
    }
    #expect(modifiers.map(\.name) == ["padding", "frame", "opacity"])
    #expect(modifiers[0].argumentLabels == ["horizontal", "value"])
    #expect(modifiers[1].argumentLabels == ["width", "height"])
    guard case let .platformValue(alternatives) = modifiers[2].arguments.first?.value else {
        Issue.record("Expected all typed platform branches")
        return
    }
    #expect(alternatives.android.value == .numberLiteral("0.6"))
    #expect(alternatives.harmonyOS.value == .numberLiteral("0.7"))
}

@Test(arguments: [
    "Text(verbatim: \"Bad\").frame(maxWidth: 100)",
    "Text(verbatim: \"Bad\").padding(.horizontal, 8, 12)",
    "Text(verbatim: \"Bad\").background(unknownColor)",
])
func builtinModifierRejectsUnsupportedValues(source: String) throws {
    let fixture = FixtureCase(name: "invalid-modifier", status: .ready,
                              input: "struct InvalidModifier: View { var body: some View { \(source) } }",
                              mapping: nil, expectedKotlin: nil, expectedArkTS: nil, expectedDiagnostics: nil)
    let result = try GoldenRunner.generate(fixture)
    #expect(result.kotlin == nil)
    #expect(result.arkTS == nil)
    #expect(!result.diagnostics.isEmpty)
    #expect(result.diagnostics.allSatisfy { $0.suggestion != nil })
}

@Test func unknownModifierKeepsItsOriginalDiagnostic() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct UnknownModifier: View { var body: some View { Text(verbatim: "Bad").blur(radius: 4) } }
    """))
    #expect(unit.diagnostics.map(\.code) == ["unsupportedModifier"])
}
