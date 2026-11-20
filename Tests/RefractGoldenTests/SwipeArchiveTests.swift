import Foundation
import Testing
import RefractFrontend
import RefractIR
import RefractGolden
import RefractMapping

private let swipeRepository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func swipeMapping() throws -> Mapping {
    try Mapping.load(contentsOf: swipeRepository.appendingPathComponent("Fixtures/interop-swipe-archive/refract.json"))
}

private func swipeFixture(_ name: String) throws -> FixtureCase {
    try CorpusLoader.load(repository: swipeRepository).first { $0.name == name }!
}

@Test func swipeArchivePreservesItemIdentityAndBothActionsOnBothBackends() throws {
    let generated = try GoldenRunner.generate(swipeFixture("interop-swipe-archive"))
    #expect(GoldenRunner.differences(for: try swipeFixture("interop-swipe-archive"), result: generated) == [])
    let kotlin = try #require(generated.kotlin)
    let arkTS = try #require(generated.arkTS)
    #expect(kotlin.contains("identifier = item.id, title = item.title"))
    #expect(kotlin.contains("onRequest = { identifier -> model.requestArchive(identifier) }"))
    #expect(kotlin.contains("onConfirm = { identifier -> model.archive(identifier) }"))
    #expect(kotlin.contains("onCancel = { model.cancelArchive() }"))
    #expect(arkTS.contains("identifier: item.id, title: item.title"))
    #expect(arkTS.contains("onRequest: (identifier: string): void => { this.model.requestArchive(identifier); }"))
    #expect(arkTS.contains("onConfirm: (identifier: string): void => { this.model.archive(identifier); }"))
    #expect(arkTS.contains("onCancel: () => { this.model.cancelArchive(); }"))
    for forbidden in ["SwipeToDismissBox(", "DropdownMenu(", "refract.runtime"] {
        #expect(!kotlin.contains(forbidden))
        #expect(!arkTS.contains(forbidden))
    }
}

@Test func swipeArchiveRejectsAnArbitraryConfirmationClosureBeforeEitherBackend() throws {
    let generated = try GoldenRunner.generate(swipeFixture("interop-swipe-reject-action"))
    #expect(generated.kotlin == nil && generated.arkTS == nil)
    #expect(generated.diagnostics.map(\.code) == ["RFSWIPE002"])
    #expect(GoldenRunner.differences(for: try swipeFixture("interop-swipe-reject-action"), result: generated) == [])
}

@Test func swipeArchiveRequiresAnIdentifiedStringListRow() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct ArchiveItem: Identifiable { let id: Int; let title: String }
    protocol ArchiveModel: RefractModel {
        var items: [ArchiveItem] { get }
        func requestArchive(_ identifier: String)
        func archive(_ identifier: String)
        func cancelArchive()
    }
    struct NativeSwipeArchiveRow: RefractNativeView {
        let identifier: String
        let title: String
        let onRequest: (String) -> Void
        let onConfirm: (String) -> Void
        let onCancel: () -> Void
        var body: some View { Text(verbatim: title) }
    }
    struct ArchiveScreen: View {
        let model: ArchiveModel
        var body: some View {
            List(model.items) { item in
                NativeSwipeArchiveRow(identifier: item.id, title: item.title,
                    onRequest: { identifier in model.requestArchive(identifier) },
                    onConfirm: { identifier in model.archive(identifier) },
                    onCancel: { model.cancelArchive() })
            }
        }
    }
    """), mapping: try! swipeMapping())
    #expect(unit.diagnostics.map(\.code).contains("RFSWIPE001"))
}

@Test func swipeArchiveRejectsUnrelatedStringActionsWithoutWideningLinkHost() {
    let declaration = NativeDeclaration(name: "OtherView", parameters: [
        NativeParameter(label: "onRequest", type: .actionString),
    ])
    let target = NativeTarget(symbol: "OtherView", module: "example.other", kind: .composable, argumentStyle: .named,
        parameters: [NativeTarget.Parameter(label: "onRequest", type: .actionString, targetType: "(String) -> Unit")],
        arguments: [NativeTarget.Argument(source: "onRequest", target: "onRequest")])
    let error = #expect(throws: InteropMappingError.self) {
        try InteropMapping.validate(declaration: declaration, target: target, platform: .android)
    }
    #expect(error?.diagnostics.map(\.code) == ["RFINPUT003"])
}
