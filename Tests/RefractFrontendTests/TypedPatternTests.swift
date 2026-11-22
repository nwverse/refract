import Foundation
import RefractArkUI
import RefractCompose
import RefractFrontend
import RefractIR
import RefractMapping
import Testing

private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func payloadMapping() throws -> Mapping {
    try Mapping.load(contentsOf: repository.appendingPathComponent("Fixtures/control-switch-payload/refract.json"))
}

private let optionalSource = """
struct OptionalGreeting: View {
    let title: String?
    var body: some View {
        if let value = title {
            Text(value)
        } else {
            Text(verbatim: "Empty")
        }
    }
}
"""

private let payloadSource = """
enum Content {
    case text(String)
    case count(Int)
}

struct ContentView: View {
    let content: Content
    var body: some View {
        switch content {
        case .text(let text):
            Text(text)
        case .count(let count):
            Text("content.count\\(count)")
        }
    }
}
"""

@Test func optionalBindingKeepsNonNullAliasInsideLazyBranch() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: optionalSource))
    #expect(unit.diagnostics.isEmpty)
    let input = try #require(unit.module.screens.first?.parameters.first)
    #expect(input.type == .string && input.isOptional)
    let kotlin = try ComposeBackend().generate(module: unit.module)
    let arkTS = try ArkUIBackend().generate(module: unit.module)
    #expect(kotlin.contains("title: String?"))
    #expect(kotlin.contains("if (title != null)"))
    #expect(kotlin.contains("val value = title"))
    #expect(kotlin.contains("Text(text = value)"))
    #expect(kotlin.contains("} else {"))
    #expect(arkTS.contains("title: string | null | undefined"))
    #expect(arkTS.contains("if (this.title !== null && this.title !== undefined)"))
    #expect(arkTS.contains("const value = this.title;"))
    #expect(arkTS.contains("Text(value)"))
    #expect(!arkTS.contains(" as "))
}

@Test func optionalBooleanBindingSupportsNestedCondition() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct OptionalEnabled: View {
        let maybeEnabled: Bool?
        var body: some View {
            if let enabled = maybeEnabled {
                if enabled {
                    Text(verbatim: "Enabled")
                } else {
                    Text(verbatim: "Disabled")
                }
            } else {
                Text(verbatim: "Unknown")
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module)
    let arkTS = try ArkUIBackend().generate(module: unit.module)
    #expect(kotlin.contains("if (enabled)"))
    #expect(arkTS.contains("if (enabled)"))
    #expect(!kotlin.contains("this.enabled"))
    #expect(!arkTS.contains("if (this.enabled)"))
}

@Test func outerOptionalBooleanAliasRemainsLocalInsideNestedBinding() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct OptionalEnabled: View {
        let maybeEnabled: Bool?
        let maybeReady: Bool?
        var body: some View {
            if let enabled = maybeEnabled {
                if let ready = maybeReady {
                    VStack {
                        if enabled {
                            Text(verbatim: "Enabled")
                        } else if ready {
                            Text(verbatim: "Disabled")
                        } else {
                            Text(verbatim: "Unavailable")
                        }
                    }
                } else {
                    Text(verbatim: "Not ready")
                }
            } else {
                Text(verbatim: "Unknown")
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module)
    let arkTS = try ArkUIBackend().generate(module: unit.module)
    #expect(kotlin.contains("if (enabled)"))
    #expect(arkTS.contains("if (enabled)"), Comment(rawValue: arkTS))
    #expect(arkTS.contains("else if (ready)"), Comment(rawValue: arkTS))
    #expect(!arkTS.contains("if (this.enabled)"))
    #expect(!arkTS.contains("else if (this.ready)"))
}

@Test func booleanPayloadConditionUsesLocalAliasInsideOptionalBinding() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum Content { case enabled(Bool) }
    struct ContentView: View {
        let content: Content
        let maybeReady: Bool?
        var body: some View {
            switch content {
            case .enabled(let enabled):
                if let ready = maybeReady {
                    if enabled {
                        Text(verbatim: "Enabled")
                    } else {
                        Text(verbatim: "Disabled")
                    }
                } else {
                    Text(verbatim: "Not ready")
                }
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module)
    let arkTS = try ArkUIBackend().generate(module: unit.module)
    #expect(kotlin.contains("if (enabled)"))
    #expect(arkTS.contains("if (enabled)"), Comment(rawValue: arkTS))
    #expect(!arkTS.contains("if (this.enabled)"))
}

@Test func booleanPayloadConditionUsesLocalAlias() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum Content { case enabled(Bool) }
    struct ContentView: View {
        let content: Content
        var body: some View {
            switch content {
            case .enabled(let enabled):
                if enabled {
                    Text(verbatim: "Enabled")
                } else {
                    Text(verbatim: "Disabled")
                }
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module)
    let arkTS = try ArkUIBackend().generate(module: unit.module)
    #expect(kotlin.contains("if (enabled)"))
    #expect(arkTS.contains("if (enabled)"), Comment(rawValue: arkTS))
    #expect(!arkTS.contains("if (this.enabled)"))
}

@Test func scalarPayloadSwitchUsesTypedLazyBranches() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: payloadSource))
    #expect(unit.diagnostics.map(\.rendered) == [])
    #expect(unit.module.enums.first?.payloadTypes == ["text": .string, "count": .int])
    let mapping = try payloadMapping()
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    let arkTS = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("public sealed interface Content {"))
    #expect(kotlin.contains("is Content.Text ->"))
    #expect(kotlin.contains("val text: String = subject.value"))
    #expect(kotlin.contains("is Content.Count ->"))
    #expect(!kotlin.contains(" as "))
    #expect(arkTS.contains("export type Content = ContentText | ContentCount;"))
    #expect(arkTS.contains("if (this.content instanceof ContentText)"))
    #expect(arkTS.contains("const text = this.content.value;"))
    #expect(arkTS.contains("Text(text)"))
    #expect(arkTS.contains("Text($r('app.string.content_count', count))"))
    #expect(arkTS.contains("} else if (this.content instanceof ContentCount)"))
    #expect(!arkTS.contains(" as "))
}

@Test func unsupportedPatternScopesRemainDiagnostics() {
    let cases: [(String, String)] = [
        ("struct Bad: View { let title: String?; var body: some View { if let title = title { Text(title) } else { Text(verbatim: \"Empty\") } } }", "RFCTRL002"),
        ("struct Bad: View { let title: String?; var body: some View { if let value = title { Text(value) } } }", "RFCTRL002"),
        ("struct Bad: View { let title: String; var body: some View { if let value = title { Text(value) } else { Text(verbatim: \"Empty\") } } }", "RFCTRL002"),
        ("struct Bad: View { let enabled: Bool?; var body: some View { if let value = enabled { Text(verbatim: \"Present\") } else { if value { Text(verbatim: \"Escaped\") } else { Text(verbatim: \"Empty\") } } } }", "RFCTRL001"),
        ("struct Bad: View { let title: String?; var body: some View { if let titleValue = title { if titleValue { Text(verbatim: \"Present\") } else { Text(verbatim: \"Invalid\") } } else { Text(verbatim: \"Empty\") } } }", "RFCTRL001"),
        ("struct Bad: View { let count: Int?; var body: some View { if let countValue = count { if countValue { Text(verbatim: \"Present\") } else { Text(verbatim: \"Invalid\") } } else { Text(verbatim: \"Empty\") } } }", "RFCTRL001"),
        ("struct Bad: View { let ratio: Double?; var body: some View { if let ratioValue = ratio { if ratioValue { Text(verbatim: \"Present\") } else { Text(verbatim: \"Invalid\") } } else { Text(verbatim: \"Empty\") } } }", "RFCTRL001"),
        ("enum Content { case text(String); case empty }; struct Bad: View { let content: Content; var body: some View { switch content { case .text(let text): Text(text); case .empty: Text(verbatim: \"Empty\") } } }", "RFCTRL006"),
        ("enum Content { case pair(String, Int) }; struct Bad: View { let content: Content; var body: some View { Text(verbatim: \"Bad\") } }", "RFCTRL006"),
        ("enum Content { case text(String) }; struct Bad: View { let content: Content; var body: some View { switch content { case .text(let text): Text(text); default: Text(verbatim: \"Other\") } } }", "RFCTRL005"),
        ("struct Bad: View { let title: String?; var body: some View { Text(title) } }", "RFSEM002"),
    ]
    for (source, expected) in cases {
        let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source))
        #expect(unit.diagnostics.map(\.code) == [expected], Comment(rawValue: source))
        #expect(unit.module.screens.isEmpty)
    }
}

@Test func payloadBindingDoesNotEscapeItsCase() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum Content { case text(String); case count(Int) }
    struct Bad: View {
        let content: Content
        var body: some View {
            switch content {
            case .text(let text): Text(text)
            case .count(let count): Text(text)
            }
        }
    }
    """))
    #expect(unit.module.screens.isEmpty)
    #expect(!unit.diagnostics.isEmpty)
    #expect(!unit.diagnostics.contains { $0.code == "RFSEM002" })
}

@Test func manuallyConstructedPatternsCannotBypassTypeValidation() {
    let optional = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Bad", parameters: [ScreenParameter(name: "title", type: .string, isOptional: true)],
               body: .optionalBinding(subject: Expression(.reference("title")), binding: "title",
                                      children: [], otherwise: [], location: nil)),
    ])
    #expect(throws: Diagnostic.self) { _ = try ComposeBackend().generate(module: optional) }
    #expect(throws: Diagnostic.self) { _ = try ArkUIBackend().generate(module: optional) }

    let missingBinding = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Bad", parameters: [ScreenParameter(name: "content", type: .string, enumName: "Content")],
               body: .switchExpression(subject: Expression(.reference("content")), enumName: "Content",
                                       cases: [SwitchCase(name: "text", children: [])], location: nil)),
    ], enums: [EnumDeclaration(name: "Content", cases: ["text"], payloadTypes: ["text": .string])])
    #expect(throws: Diagnostic.self) { _ = try ComposeBackend().generate(module: missingBinding) }
    #expect(throws: Diagnostic.self) { _ = try ArkUIBackend().generate(module: missingBinding) }
}

@Test func invalidEnumPayloadDeclarationCannotBeEmitted() {
    let module = Module(sourceFile: "Input.swift", screens: [],
                        enums: [EnumDeclaration(name: "Content", cases: ["text"], payloadTypes: ["other": .string])])
    #expect(throws: Diagnostic.self) { _ = try ComposeBackend().generate(module: module) }
    #expect(throws: Diagnostic.self) { _ = try ArkUIBackend().generate(module: module) }
}
