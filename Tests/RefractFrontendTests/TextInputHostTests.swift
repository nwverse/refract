import Testing
import RefractIR
@testable import RefractFrontend
import RefractMapping

@Test func textInputHostBuildsBoundedBindingAndModelCallbacks() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: hostSource))
    #expect(unit.diagnostics.isEmpty)
    #expect(unit.module.nativeDeclarations.map(\.kind) == [.textInputHost])
    #expect(unit.module.nativeDeclarations.first?.parameters.map(\.label)
        == ["draft", "focusRequest", "onDraftCommit", "onCommit"])
    guard let screen = unit.module.screens.first, case let .native(component, _) = screen.body else {
        Issue.record("Expected a native text-input host")
        return
    }
    #expect(component.arguments.map(\.type) == [.string, .int, .actionString, .action])
    #expect(component.arguments[2].action == .modelMethod(model: "model", name: "commitDraft", arguments: []))
    #expect(component.arguments[3].action == .modelMethod(model: "model", name: "commit", arguments: []))
}

@Test(arguments: [
    "Text(\"Message\")",
    "TextField(\"Message\", text: $draft)",
    "TextField(\"Message\", text: $draft).focused($isHostFocused).onChange(of: focusRequest) { _, _ in isHostFocused = true }.onSubmit { onDraftCommit(draft); onCommit() }",
    "TextField(\"Message\", text: $draft).focused($isHostFocused).submitLabel(.done).onChange(of: focusRequest) { _, _ in isHostFocused = false }.onSubmit { onDraftCommit(draft); onCommit() }",
    "TextField(\"Message\", text: $draft).focused($isHostFocused).submitLabel(.done).onChange(of: focusRequest) { _, _ in isHostFocused = true }.onSubmit { onCommit(); onDraftCommit(draft) }",
])
func textInputHostRejectsMissingOrReorderedNativeSemantics(_ body: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct NativeTextInputHost: RefractTextInputHost {
        @Binding var draft: String
        let focusRequest: Int
        let onDraftCommit: (String) -> Void
        let onCommit: () -> Void
        @FocusState private var isHostFocused: Bool
        var body: some View { \(body) }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFINPUT001"])
    #expect(unit.diagnostics[0].location?.line == 7)
    #expect(unit.module.nativeDeclarations.isEmpty)
}

@Test func textInputHostRejectsNativeBodyAndPreservesCallerDiagnostic() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: hostSource.replacingOccurrences(
        of: "TextField(\"Message\", text: $draft)", with: "Text(\"Message\")")))
    #expect(unit.diagnostics.map(\.code) == ["RFINPUT001", "RFINPUT002"])
    #expect(unit.diagnostics.first?.message.contains("TextField") == true)
    #expect(unit.module.nativeDeclarations.isEmpty)
    #expect(unit.module.screens.isEmpty)
}

@Test func textInputHostAcceptsCanonicalMultilineBody() {
    let source = hostSource.replacingOccurrences(
        of: ".onChange(of: focusRequest) { _, _ in isHostFocused = true }",
        with: ".onChange(of: focusRequest) { _, _ in\n                isHostFocused = true\n            }")
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source))
    #expect(unit.diagnostics.isEmpty)
}

@Test func textInputHostRejectsLocalDraftAndArbitraryCallbacks() {
    let source = hostSource
        .replacingOccurrences(of: "@Binding var draft: String\n    @Binding var focusRequest: Int", with: "@State private var draft: String = \"\"\n    @Binding var focusRequest: Int")
        .replacingOccurrences(of: "onCommit: { model.commit() }", with: "onCommit: { draft = \"\" }")
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source))
    #expect(unit.diagnostics.filter { $0.code == "RFINPUT002" }.count == 2)
    #expect(unit.hasErrors)
}

@Test(arguments: [
    "@Binding var draft: String\n    let focusRequest: Int\n    let onDraftCommit: (String) -> Void\n    let onCommit: () -> Void",
    "@Binding var draft: String\n    @FocusState private var isHostFocused: Bool\n    let focusRequest: Int\n    let onDraftCommit: (String) -> Void",
])
func textInputHostRejectsIncompleteSignature(_ properties: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct NativeTextInputHost: RefractTextInputHost {
        \(properties)
        var body: some View {
            TextField("Message", text: $draft)
                .focused($isHostFocused)
                .submitLabel(.done)
                .onChange(of: focusRequest) { _, _ in isHostFocused = true }
                .onSubmit {
                    onDraftCommit(draft)
                    onCommit()
                }
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFINPUT001"])
}

@Test func ordinaryNativeViewKeepsGenericNoArgumentActionOnly() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol SaveModel: RefractModel { func save() }
    struct ArbitraryEditor: RefractNativeView {
        let onCommit: () -> Void
        var body: some View { Text(verbatim: "iOS") }
    }
    struct Screen: View {
        let model: SaveModel
        var body: some View { ArbitraryEditor(onCommit: { model.save() }) }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
}

@Test func ordinaryNativeViewRejectsHostDraftCallbackMapping() throws {
    let declaration = NativeDeclaration(name: "ArbitraryEditor", parameters: [
        NativeParameter(label: "onDraftCommit", type: .actionString),
    ])
    let target = NativeTarget(symbol: "ArbitraryEditor", module: "example.input", kind: .composable,
                              argumentStyle: .named,
                              parameters: [.init(label: "onDraftCommit", type: .actionString)],
                              arguments: [.init(source: "onDraftCommit", target: "onDraftCommit")])
    #expect(throws: InteropMappingError.self) {
        try InteropMapping.validate(declaration: declaration, target: target, platform: .android)
    }

    // Selection owns a separate typed destination action; it does not inherit host draft semantics.
    let selection = NativeDeclaration(name: "NativeSelectionMessage", parameters: [
        NativeParameter(label: "onLink", type: .actionString),
    ])
    let selectionTarget = NativeTarget(symbol: "NativeSelectionMessage", module: "example.selection", kind: .composable,
                                       argumentStyle: .named,
                                       parameters: [.init(label: "onLink", type: .actionString)],
                                       arguments: [.init(source: "onLink", target: "onLink")])
    _ = try InteropMapping.validate(declaration: selection, target: selectionTarget, platform: .android)
}

private let hostSource = """
import SwiftUI

struct NativeTextInputHost: RefractTextInputHost {
    @Binding var draft: String
    let focusRequest: Int
    let onDraftCommit: (String) -> Void
    let onCommit: () -> Void
    @FocusState private var isHostFocused: Bool
    var body: some View {
        TextField("Message", text: $draft)
            .focused($isHostFocused)
            .submitLabel(.done)
            .onChange(of: focusRequest) { _, _ in isHostFocused = true }
            .onSubmit {
                onDraftCommit(draft)
                onCommit()
            }
    }
}
protocol ComposerModel: RefractModel {
    func commitDraft(_ value: String)
    func commit()
}
struct ComposerScreen: View {
    @Binding var draft: String
    @Binding var focusRequest: Int
    let model: ComposerModel
    var body: some View {
        NativeTextInputHost(
            draft: $draft,
            focusRequest: focusRequest,
            onDraftCommit: { value in model.commitDraft(value) },
            onCommit: { model.commit() }
        )
    }
}
"""
