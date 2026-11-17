import Testing
import RefractIR
@testable import RefractFrontend

@Test func textInputHostBuildsBoundedBindingAndModelCallbacks() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: hostSource))
    #expect(unit.diagnostics.isEmpty)
    #expect(unit.module.nativeDeclarations.map(\.kind) == [.textInputHost])
    #expect(unit.module.nativeDeclarations[0].parameters.map(\.label)
        == ["draft", "focusRequest", "onDraftCommit", "onCommit"])
    guard case let .native(component, _) = unit.module.screens[0].body else {
        Issue.record("Expected a native text-input host")
        return
    }
    #expect(component.arguments.map(\.type) == [.string, .int, .actionString, .action])
    #expect(component.arguments[2].action == .modelMethod(model: "model", name: "commitDraft", arguments: []))
    #expect(component.arguments[3].action == .modelMethod(model: "model", name: "commit", arguments: []))
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
        var body: some View { TextField("Message", text: $draft) }
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

@Test func ordinaryNativeViewRejectsHostStringCallback() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct ArbitraryEditor: RefractNativeView {
        let onDraftCommit: (String) -> Void
        var body: some View { Text(verbatim: "iOS") }
    }
    struct Screen: View {
        var body: some View { ArbitraryEditor(onDraftCommit: { _ in }) }
    }
    """))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.contains { $0.code == "RFNATIVE001" })
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
            .onChange(of: focusRequest) { _, _ in isHostFocused = true }
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
