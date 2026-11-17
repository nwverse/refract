import Foundation
import RefractArkUI
import RefractCompose
import RefractFrontend
import RefractIR
import RefractMapping
import Testing

private let navigationFixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/navigation-deep-restoration")

@Test func threeLevelGraphForwardsTheSameTypedHostOperation() throws {
    let input = try String(contentsOf: navigationFixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    let mappingData = try Data(contentsOf: navigationFixture.appendingPathComponent("refract.json"))
    let mapping = try Mapping.load(data: mappingData, file: "refract.json", resourceBaseURL: navigationFixture)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input), mapping: mapping)
    #expect(unit.diagnostics.isEmpty)
    let detail = try #require(unit.module.screens.first { $0.name == "DeepDetailScreen" })
    let editor = try #require(unit.module.screens.first { $0.name == "DeepEditorScreen" })
    #expect(detail.navigation == NavigationOperation(enumName: "DeepRoute"))
    #expect(editor.navigation == nil)

    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("public fun DeepDetailScreen(\n    model: DeepNavigationModel,\n    onPathNavigate: (DeepRoute) -> Unit,"))
    #expect(kotlin.contains("DeepDetailScreen(model = model, onPathNavigate = onPathNavigate, modifier = modifier)"))
    #expect(kotlin.contains("public fun DeepNavigationScreenDestinations(\n    destination: DeepRoute,\n    model: DeepNavigationModel,\n    onPathNavigate: (DeepRoute) -> Unit,"))
    #expect(!kotlin.contains("rememberSaveable"))
    #expect(!kotlin.contains("NavController"))
    #expect(!kotlin.contains("Bundle"))
    #expect(!kotlin.contains("restoreState"))

    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("DeepDetailScreen({ model: this.model, onPathNavigate: this.onPathNavigate })"))
    #expect(ark.contains("@Event onPathNavigate: (destination: DeepRoute) => void"))
    #expect(!ark.contains("NavPathStack"))
    #expect(!ark.contains("AppStorage"))
}

@Test func unregisteredDestinationLinksAreRejectedByGraphBinding() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum Route: Hashable { case detail }
    protocol DetailModel: RefractModel { var title: String { get } }
    struct DetailScreen: View {
        let model: DetailModel
        var body: some View { NavigationLink("navigation.open", value: Route.detail) }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFNAV003"])
    #expect(unit.diagnostics.first?.message.contains("enclosing graph's finite enum") == true)
}
