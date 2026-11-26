import Foundation
import Testing
import RefractIR
import RefractMapping
import RefractFrontend
import RefractGolden
@testable import RefractCompose
import RefractArkUI

// Selection editing on a TextField: frontend accepts a typed (Int, Int, action) triple and
// the Compose backend emits a selection-aware TextField that drives the model action.
@Test func selectionFieldEmitsSelectionAwareTextField() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel {
        func replaceSelection(start: Int, end: Int, replacement: String)
    }
    struct Screen: View {
        let model: Model
        @State private var text: String = ""
        var body: some View {
            TextField("settings.display.name", text: $text)
                .refractNativeModifier(.textSelection(start: 0, end: 0, action: "replaceSelection"))
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .nativeModifier(_, operations, _) = unit.module.screens[0].body,
          operations.count == 1,
          case let .textSelection(_, _, action) = operations[0].operation else {
        Issue.record("Expected a single textSelection operation, got \(unit.module.screens[0].body)")
        return
    }
    #expect(action == "replaceSelection")
    let mapping = try Mapping.load(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/v0-text-input/refract.json"))
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("TextFieldValue(text = text, selection = TextRange(0, 0))"))
    #expect(kotlin.contains("model.replaceSelection(start = updated.selection.start, end = updated.selection.end, replacement = updated.text)"))
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("onTextSelectionChange"))
    #expect(ark.contains("this.model.replaceSelection(selectionStart, selectionEnd, this.text);"))
}

// Selection edits must bind to a local @State String, not to a parent binding or a model property.
@Test func selectionFieldRequiresLocalStateString() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel {
        func replaceSelection(start: Int, end: Int, replacement: String)
    }
    struct Screen: View {
        let model: Model
        @Binding var text: String
        var body: some View {
            TextField("settings.display.name", text: $text)
                .refractNativeModifier(.textSelection(start: 0, end: 0, action: "replaceSelection"))
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    #expect(throws: Diagnostic.self) { try ComposeBackend().generate(module: unit.module) }
}

// Selection requires a TextField receiver; other views are rejected.
@Test func selectionRejectsNonTextFieldReceiver() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel {
        func replaceSelection(start: Int, end: Int, replacement: String)
    }
    struct Screen: View {
        let model: Model
        var body: some View {
            Text(verbatim: "Title")
                .refractNativeModifier(.textSelection(start: 0, end: 0, action: "replaceSelection"))
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE005"])
}

// Selection requires a declared model method by name.
@Test func selectionRejectsUndeclaredModelAction() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel { }
    struct Screen: View {
        let model: Model
        @State private var text: String = ""
        var body: some View {
            TextField("settings.display.name", text: $text)
                .refractNativeModifier(.textSelection(start: 0, end: 0, action: "missing"))
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let diagnostic = #expect(throws: Diagnostic.self) { try ComposeBackend().generate(module: unit.module) }
    #expect(diagnostic?.code == "RFNATIVE005")
}

// Drag source with a typed String payload lowers to Compose's dragAndDropSource with a plain-text ClipData.
@Test func dragSourceEmitsTypedStringClipData() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Screen: View {
        @State private var note: String = "hello"
        var body: some View {
            Text(verbatim: "Drag me")
                .refractNativeModifier(.dragPayload(kind: "note", value: note))
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module)
    #expect(kotlin.contains("dragAndDropSource("))
    #expect(kotlin.contains("ClipData.newPlainText(\"note\", note)"))
    #expect(kotlin.contains("@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)"))
}

// An outer optional scalar stays local when a lazy row's drag event reads its payload.
@Test func dragPayloadKeepsOptionalAliasInsideForEachRow() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct OptionalDragItem: Identifiable {
        let id: String
        let title: String
    }

    protocol OptionalDragModel: RefractModel {
        var items: [OptionalDragItem] { get }
        func receiveDrop(kind: String, payload: String)
    }

    struct OptionalNativeList: View {
        let model: OptionalDragModel
        let title: String?

        var body: some View {
            if let value = title {
                List {
                    ForEach(model.items) { item in
                        Text(value)
                            .refractNativeModifier(.dragPayload(kind: "note", value: value))
                    }
                }
            } else {
                Text(verbatim: "Empty")
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module)
    let ark = try ArkUIBackend().generate(module: unit.module)
    #expect(kotlin.contains("ClipData.newPlainText(\"note\", value)"))
    #expect(ark.contains("const value = this.title;"))
    #expect(ark.contains("Text(value)"))
    #expect(ark.contains("event.setData({ 'note': value } as Record<string, string>);"), Comment(rawValue: ark))
    #expect(!ark.contains("'note': this.value"))
    #expect(ark.contains("(item: OptionalDragItem): string => item.id"))
}

// Drop target invokes the model action with the matching kind and a non-empty payload.
@Test func dropTargetInvokesModelActionOnNonEmptyPayload() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel {
        func receiveDrop(kind: String, payload: String)
    }
    struct Screen: View {
        let model: Model
        var body: some View {
            Text(verbatim: "Drop here")
                .refractNativeModifier(.dropTarget(kind: "note", action: "receiveDrop"))
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module)
    #expect(kotlin.contains("dragAndDropTarget("))
    #expect(kotlin.contains("model.receiveDrop(kind = \"note\", payload = text)"))
    #expect(kotlin.contains("if (text.isEmpty()) return false"))
}

// Closed native callback names must resolve to one current-screen model with the exact signature.
@Test(arguments: [
    "func receiveDrop(kind: Int, payload: Bool)",
    "func receiveDrop(kind: String)",
    "@refractAsync func receiveDrop(kind: String, payload: String)",
    "func receiveDrop(_ kind: String, payload: String)",
])
func dropTargetRejectsAnIncompatibleOrAsyncAction(_ declaration: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel { \(declaration) }
    struct Screen: View {
        let model: Model
        var body: some View {
            Text(verbatim: "Drop")
                .refractNativeModifier(.dropTarget(kind: "note", action: "receiveDrop"))
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    for backend in ["compose", "arkui"] {
        let diagnostic = #expect(throws: Diagnostic.self) {
            if backend == "compose" { _ = try ComposeBackend().generate(module: unit.module) }
            else { _ = try ArkUIBackend().generate(module: unit.module) }
        }
        #expect(diagnostic?.code == "RFNATIVE005", "\(backend) accepted \(declaration)")
    }
}

@Test func textSelectionRejectsAWrongSignatureOnBothBackends() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel { func replaceSelection(start: Int, end: Int) }
    struct Screen: View {
        let model: Model
        @State private var text: String = ""
        var body: some View {
            TextField("settings.display.name", text: $text)
                .refractNativeModifier(.textSelection(start: 0, end: 0, action: "replaceSelection"))
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    for backend in ["compose", "arkui"] {
        let diagnostic = #expect(throws: Diagnostic.self) {
            if backend == "compose" { _ = try ComposeBackend().generate(module: unit.module) }
            else { _ = try ArkUIBackend().generate(module: unit.module) }
        }
        #expect(diagnostic?.code == "RFNATIVE005", "\(backend) accepted an incomplete signature")
    }
}

@Test func nativeActionExternalLabelsDoNotRequireMatchingLocalNames() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel {
        func receiveDrop(kind: String, payload value: String)
        func replaceSelection(start: Int, end: Int, replacement newText: String)
    }
    struct Screen: View {
        let model: Model
        @State private var text: String = ""
        var body: some View {
            VStack {
                Text(verbatim: "Drop")
                    .refractNativeModifier(.dropTarget(kind: "note", action: "receiveDrop"))
                TextField("settings.display.name", text: $text)
                    .refractNativeModifier(.textSelection(start: 0, end: 0, action: "replaceSelection"))
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let mapping = try Mapping.load(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/v0-text-input/refract.json"))
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("public fun receiveDrop(kind: String, value: String)"))
    #expect(kotlin.contains("model.receiveDrop(kind = \"note\", value = text)"))
    #expect(kotlin.contains("model.replaceSelection(start = updated.selection.start, end = updated.selection.end, newText = updated.text)"))
    #expect(ark.contains("this.model.receiveDrop('note', payload);"))
    #expect(ark.contains("this.model.replaceSelection(selectionStart, selectionEnd, this.text);"))
}

@Test func nativeActionsBindToTheCurrentScreenInsteadOfAnotherScreensModel() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol ModelA: RefractModel { func receiveDrop(kind: String, payload: String) }
    protocol ModelB: RefractModel { func receiveDrop(kind: String, payload: String) }
    struct FirstScreen: View {
        let modelA: ModelA
        var body: some View { Text(verbatim: "First") }
    }
    struct DropScreen: View {
        let modelB: ModelB
        var body: some View {
            Text(verbatim: "Drop")
                .refractNativeModifier(.dropTarget(kind: "note", action: "receiveDrop"))
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module)
    let ark = try ArkUIBackend().generate(module: unit.module)
    #expect(kotlin.contains("modelB.receiveDrop(kind = \"note\", payload = text)"))
    #expect(ark.contains("this.modelB.receiveDrop('note', payload);"))
    #expect(!kotlin.contains("modelA.receiveDrop("))
    #expect(!ark.contains("this.modelA.receiveDrop("))
}

@Test func nativeActionsRejectMultipleMatchingModelsOnOneScreen() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol ModelA: RefractModel { func receiveDrop(kind: String, payload: String) }
    protocol ModelB: RefractModel { func receiveDrop(kind: String, payload: String) }
    struct Screen: View {
        let modelA: ModelA
        let modelB: ModelB
        var body: some View {
            Text(verbatim: "Drop")
                .refractNativeModifier(.dropTarget(kind: "note", action: "receiveDrop"))
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    for backend in ["compose", "arkui"] {
        let diagnostic = #expect(throws: Diagnostic.self) {
            if backend == "compose" { _ = try ComposeBackend().generate(module: unit.module) }
            else { _ = try ArkUIBackend().generate(module: unit.module) }
        }
        #expect(diagnostic?.code == "RFNATIVE005", "\(backend) chose an arbitrary model")
    }
}

// Payload value must be a typed String; an Int literal is rejected.
@Test func dragPayloadRejectsNonStringValue() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Screen: View {
        var body: some View {
            Text(verbatim: "Drag")
                .refractNativeModifier(.dragPayload(kind: "note", value: 42))
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE005"])
}

// Payload kind must be a lowercase ASCII identifier.
@Test func dragPayloadRejectsNonIdentifierKind() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Screen: View {
        @State private var note: String = "hello"
        var body: some View {
            Text(verbatim: "Drag")
                .refractNativeModifier(.dragPayload(kind: "Note-Kind", value: note))
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE005"])
}

// Drop target action must name a method declared on a model protocol used by this screen.
@Test func dropTargetRejectsUndeclaredModelAction() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel { }
    struct Screen: View {
        let model: Model
        var body: some View {
            Text(verbatim: "Drop")
                .refractNativeModifier(.dropTarget(kind: "note", action: "missing"))
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let diagnostic = #expect(throws: Diagnostic.self) { try ComposeBackend().generate(module: unit.module) }
    #expect(diagnostic?.code == "RFNATIVE005")
}

// Unicode (non-BMP emoji + CJK) round-trips through a typed String payload.
@Test func dragPayloadSupportsUnicodeStrings() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Screen: View {
        @State private var note: String = "🌸 汉字 mixed"
        var body: some View {
            Text(verbatim: "Drag")
                .refractNativeModifier(.dragPayload(kind: "note", value: note))
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module)
    // The payload is a runtime value; we assert the path is wired and no lossy escaping is applied.
    #expect(kotlin.contains("ClipData.newPlainText(\"note\", note)"))
}

// Empty payload (runtime "") cancels the drop without invoking the model action.
// This is exercised by the Native JVM test in tests/jvm/... which simulates the generated wrapper.
// The generator-side guarantee is the `if (text.isEmpty()) return false` line.
@Test func dropTargetCancelsOnEmptyPayload() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    protocol Model: RefractModel {
        func receiveDrop(kind: String, payload: String)
    }
    struct Screen: View {
        let model: Model
        var body: some View {
            Text(verbatim: "Drop")
                .refractNativeModifier(.dropTarget(kind: "note", action: "receiveDrop"))
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let kotlin = try ComposeBackend().generate(module: unit.module)
    #expect(kotlin.contains("if (text.isEmpty()) return false"))
}
