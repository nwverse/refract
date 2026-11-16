import Foundation
import Testing
@testable import RefractFrontend
import RefractCompose
import RefractArkUI
import RefractMapping
import RefractIR

@Test func customButtonLabelPreservesModelActionAndTypedSymbols() throws {
    let source = SourceFile(path: "Input.swift", contents: """
    protocol ControlsModel: RefractModel {
        func save()
    }
    struct LeafControls: View {
        let model: ControlsModel
        var body: some View {
            Button {
                model.save()
            } label: {
                Label("settings.save", systemImage: "checkmark")
            }
        }
    }
    """)
    let unit = Frontend.parse(source)
    #expect(unit.diagnostics.isEmpty)
    let mapping = try Mapping.load(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/v0-leaf-controls/refract.json"))
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("Button(onClick = { model.save() }"))
    #expect(kotlin.contains("Icons.Default.Check"))
    #expect(kotlin.contains("Text(text = stringResource(R.string.settings_save))"))
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("Image($r('app.media.confirm'))"))
    #expect(ark.contains("this.model.save();"))
}

@Test func unmappedSystemImageIsADiagnostic() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct BadImage: View {
        var body: some View { Image(systemName: "unknown.symbol") }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    #expect(throws: Diagnostic.self) {
        _ = try ComposeBackend().generate(module: unit.module)
    }
    #expect(throws: Diagnostic.self) {
        _ = try ArkUIBackend().generate(module: unit.module)
    }
}
