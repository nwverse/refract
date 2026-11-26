import Testing
import Foundation
import RefractIR
@testable import RefractFrontend
import RefractCompose
import RefractArkUI
import RefractMapping

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

@Test func textInputHostPreservesValidatedTargetSymbolsAndLabels() throws {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/interop-text-input-host")
    let input = try String(contentsOf: directory.appendingPathComponent("Input.swift"), encoding: .utf8)
    let mapping = try Mapping.load(contentsOf: directory.appendingPathComponent("refract.json"))
    var android = mapping.android
    var harmonyOS = mapping.harmonyOS
    android.imports = [NativeImport(module: "example.input.EditorHost", symbols: ["EditorHost"])]
    harmonyOS.imports = [NativeImport(module: "example.input", symbols: ["EditorComponent"])]
    let source = try #require(mapping.android.nativeComponents["NativeTextInputHost"])
    let androidArguments = [
        ArgumentBinding(source: "draft", target: "text"),
        ArgumentBinding(source: "focusRequest", target: "focusToken"),
        ArgumentBinding(source: "onDraftCommit", target: "submitDraft"),
        ArgumentBinding(source: "onCommit", target: "submit"),
    ]
    let harmonySource = try #require(mapping.harmonyOS.nativeComponents["NativeTextInputHost"])
    let harmonyArguments = [
        ArgumentBinding(source: "draft", target: "draftValue"),
        ArgumentBinding(source: "focusRequest", target: "focusToken"),
        ArgumentBinding(source: "onDraftCommit", target: "submitDraft"),
        ArgumentBinding(source: "onCommit", target: "submit"),
    ]
    android.nativeComponents["NativeTextInputHost"] = Component(
        parameters: source.parameters, content: source.content, contentParameter: source.contentParameter,
        modifiers: source.modifiers, target: "EditorHost", argumentStyle: source.argumentStyle,
        arguments: androidArguments, modifierParameter: source.modifierParameter,
        attributes: source.attributes, module: "example.input", kind: source.kind,
        targetTypes: source.targetTypes)
    harmonyOS.nativeComponents["NativeTextInputHost"] = Component(
        parameters: harmonySource.parameters, content: harmonySource.content, contentParameter: harmonySource.contentParameter,
        modifiers: harmonySource.modifiers, target: "EditorComponent", argumentStyle: harmonySource.argumentStyle,
        arguments: harmonyArguments, modifierParameter: harmonySource.modifierParameter,
        attributes: harmonySource.attributes, module: "example.input", kind: harmonySource.kind,
        targetTypes: harmonySource.targetTypes)
    let remapped = Mapping(android: android, harmonyOS: harmonyOS)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input), mapping: remapped)
    #expect(unit.diagnostics.isEmpty)

    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: remapped)
    #expect(kotlin.contains("import example.input.EditorHost"))
    #expect(kotlin.contains("EditorHost("))
    #expect(kotlin.contains("text = draft,"))
    #expect(kotlin.contains("onTextChange = onDraftChange,"))
    #expect(kotlin.contains("focusToken = focusRequest,"))
    #expect(kotlin.contains("submitDraft = { value -> model.commitDraft(value) },"))
    #expect(kotlin.contains("submit = { model.commit() },"))
    #expect(!kotlin.contains("NativeTextInputHost("))

    let ark = try ArkUIBackend().generate(module: unit.module, mapping: remapped)
    #expect(ark.contains("import { EditorComponent } from 'example.input';"))
    #expect(ark.contains("EditorComponent({"))
    #expect(ark.contains("draftValue: this.draft,"))
    #expect(ark.contains("onDraftValueChange: (value: string): void => { this.onDraftChange(value); },"))
    #expect(ark.contains("focusToken: this.focusRequest,"))
    #expect(ark.contains("submitDraft: (value: string): void => { this.model.commitDraft(value); },"))
    #expect(ark.contains("submit: (): void => { this.model.commit(); },"))
    #expect(!ark.contains("NativeTextInputHost({"))
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
