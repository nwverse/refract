import Testing
import RefractIR
@testable import RefractFrontend

@Test func localizedKeyAndVerbatimHaveDifferentIR() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Strings: View {
        var body: some View {
            VStack {
                Text("settings.title")
                Text(LocalizedStringKey("settings.subtitle"))
                Text(String(localized: "settings.footer"))
                Text(verbatim: "Debug: $value")
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    #expect(!unit.diagnostics.contains { $0.code == "unsupportedViewBody" || $0.code == "R.string.interpolation" })
    let children = try stackChildren(unit)
    #expect(children.count == 4)
    for (index, key) in ["settings.title", "settings.subtitle", "settings.footer"].enumerated() {
        guard case let .text(expression, _, _) = children[index],
              case let .localizedText(text) = expression.value else {
            Issue.record("Expected localized text")
            return
        }
        #expect(text.key == key)
        #expect(text.arguments.isEmpty)
    }
    guard case let .text(expression, _, _) = children[3] else {
        Issue.record("Expected verbatim text")
        return
    }
    #expect(expression.value == .verbatimText("Debug: $value"))
}

@Test func formattedTextRetainsStaticKeyAndTypedInputs() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Greeting: View {
        let name: String
        let count: Int
        let ratio: Double
        var body: some View {
            Text("profile.greeting\\(name)\\(count)\\(ratio)")
        }    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let screen = try #require(unit.module.screens.first)
    #expect(screen.parameters.map(\.type) == [.string, .int, .double])
    guard case let .text(expression, _, _) = screen.body,
          case let .localizedText(text) = expression.value else {
        Issue.record("Expected formatted localized text")
        return
    }
    #expect(text.key == "profile.greeting")
    #expect(text.arguments.map(\.type) == [.string, .int, .double])
    #expect(text.arguments.map(\.value) == [.reference("name"), .reference("count"), .reference("ratio")])
}

@Test func modelPropertyInterpolationRetainsDeclaredTypeAndKey() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol CountModel: RefractModel {
        var count: Int { get }
    }
    struct FormattedText: View {
        let model: CountModel
        var body: some View {
            Text("settings.item.count\\(model.count)")
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let text = try #require(unit.module.screens.first?.body.textExpression)
    guard case let .localizedText(localized) = text.value else {
        Issue.record("Expected localized model interpolation")
        return
    }
    #expect(localized.key == "settings.item.count")
    #expect(localized.arguments.map(\.type) == [.int])
    #expect(localized.arguments.map(\.value) == [.valueProperty(.model(model: "model", property: "count"))])
}

@Test func platformTextIsVerbatimAndKeepsTargetBranches() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct PlatformText: View {
        var body: some View { Text(refractValue(ios: "iOS", android: "Android", harmonyOS: "HarmonyOS")) }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .text(expression, _, _) = unit.module.screens.first?.body,
          case let .platformValue(values) = expression.value else {
        Issue.record("Expected typed platform text")
        return
    }
    #expect(values.android.value == .verbatimText("Android"))
    #expect(values.harmonyOS.value == .verbatimText("HarmonyOS"))
}

@Test func accidentalLiteralSuggestsVerbatimText() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct LiteralResource: View {
        var body: some View { Text(String("Hello")) }
    }
    """))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.contains {
        $0.code == "R.string.unsupported_expression" && $0.suggestion?.contains("Text(verbatim:)") == true
    })
    #expect(unit.module.screens.isEmpty)
}

@Test func unknownViewKeepsItsNativeDiagnosticWithoutBodyInterpolationErrors() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Bad: View { var body: some View { Gauge("photo") } }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE001"])
    #expect(!unit.diagnostics.contains { $0.code == "unsupportedViewBody" || $0.code == "R.string.interpolation" })
}

@Test(arguments: [
    "Text(\"Hello\")",
    "Text(LocalizedStringKey(dynamicKey))",
    "Text(\"profile.greeting \\(unknown)\")",
    "Text(verbatim: \"Hello \\(name)\")",
    "Text(String(localized: \"key\", arguments: [name]))",
])
func invalidLocalizedTextIsDiagnosed(source: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Bad: View {
        let name: String
        let dynamicKey: String
        var body: some View { \(source) }
    }
    """))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.contains { $0.code.hasPrefix("R.string.") })
}

private extension ViewNode {
    var textExpression: Expression? {
        guard case let .text(expression, _, _) = self else { return nil }
        return expression
    }
}

private func stackChildren(_ unit: TranslationUnit) throws -> [ViewNode] {
    guard case let .stack(_, children, _, _) = unit.module.screens.first?.body else {
        Issue.record("Expected a stack")
        return []
    }
    return children
}
