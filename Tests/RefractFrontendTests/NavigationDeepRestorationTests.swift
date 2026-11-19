import Foundation
import FoundationXML
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

@Test func deepStackDestinationRetainsTypedModalAndNavigationOperations() throws {
    let navigationMapping = try Mapping.load(data: Data(contentsOf: navigationFixture.appendingPathComponent("refract.json")),
                                            file: "refract.json", resourceBaseURL: navigationFixture)
    let modalFixture = navigationFixture.deletingLastPathComponent().appendingPathComponent("modal-native-host")
    let modalMapping = try Mapping.load(data: Data(contentsOf: modalFixture.appendingPathComponent("refract.json")),
                                       file: "refract.json", resourceBaseURL: modalFixture)
    let resources = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: resources) }
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    let androidCatalog = try XMLDocument(contentsOf: navigationFixture.appendingPathComponent("values/strings.xml"))
    let modalAndroidCatalog = try XMLDocument(contentsOf: modalFixture.appendingPathComponent("values/strings.xml"))
    for child in modalAndroidCatalog.rootElement()?.children ?? [] {
        if let element = child as? XMLElement, let copy = element.copy() as? XMLElement {
            androidCatalog.rootElement()?.addChild(copy)
        }
    }
    try androidCatalog.xmlData.write(to: resources.appendingPathComponent("strings.xml"))
    var harmonyCatalog = try JSONSerialization.jsonObject(
        with: Data(contentsOf: navigationFixture.appendingPathComponent("string.json"))) as! [String: [[String: String]]]
    let modalHarmonyCatalog = try JSONSerialization.jsonObject(
        with: Data(contentsOf: modalFixture.appendingPathComponent("resources/base/element/string.json"))) as! [String: [[String: String]]]
    harmonyCatalog["string", default: []].append(contentsOf: modalHarmonyCatalog["string"] ?? [])
    try JSONSerialization.data(withJSONObject: harmonyCatalog).write(to: resources.appendingPathComponent("string.json"))
    var android = navigationMapping.android
    android.resources.catalog = "strings.xml"
    android.resources.strings.merge(modalMapping.android.resources.strings) { _, modal in modal }
    var harmonyOS = navigationMapping.harmonyOS
    harmonyOS.resources.catalog = "string.json"
    harmonyOS.resources.strings.merge(modalMapping.harmonyOS.resources.strings) { _, modal in modal }
    let mapping = Mapping(android: android, harmonyOS: harmonyOS, resourceBaseURL: resources)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum Route: Hashable {
        case detail
        case editor
    }
    protocol Model: RefractModel { func confirm() }
    struct DetailScreen: View {
        let model: Model
        @Binding var visible: Bool
        var body: some View {
            VStack {
                NavigationLink("navigation.open.editor", value: Route.editor)
            }
            .alert("modal.delete.title", isPresented: $visible) {
                Button("modal.delete.confirm") { model.confirm() }
                Button("modal.delete.cancel", role: .cancel) {}
            } message: { Text("modal.delete.message") }
        }
    }
    struct EditorScreen: View {
        let model: Model
        @Binding var visible: Bool
        var body: some View { Text(verbatim: "Editor") }
    }
    struct RootScreen: View {
        let model: Model
        @State private var path: [Route] = []
        var body: some View {
            NavigationStack(path: $path) {
                VStack { NavigationLink("navigation.open.detail", value: .detail) }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .detail: DetailScreen(model: model)
                    case .editor: EditorScreen(model: model)
                    }
                }
            }
        }
    }
    """), mapping: mapping)
    #expect(unit.diagnostics.isEmpty)
    let detail = try #require(unit.module.screens.first { $0.name == "DetailScreen" })
    #expect(detail.navigation == NavigationOperation(enumName: "Route"))
    #expect(detail.modals.map(\.kind) == [.alert])

    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("onVisiblePresent: () -> Unit = {},"))
    #expect(kotlin.contains("onPathNavigate: (Route) -> Unit,"))
    #expect(kotlin.contains("AlertDialog("))
    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("@Event onVisiblePresent: () => void"))
    #expect(ark.contains("@Event onPathNavigate: (destination: Route) => void"))
    #expect(ark.contains("@Monitor('visible')"))
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
