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

private func stackChildren(_ unit: TranslationUnit) throws -> [ViewNode] {
    guard case let .stack(_, children, _, _) = unit.module.screens.first?.body else {
        Issue.record("Expected a stack")
        return []
    }
    return children
}
