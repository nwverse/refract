import Foundation
import RefractArkUI
import RefractCompose
import RefractFrontend
import RefractIR
import RefractMapping
import Testing

private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Test func typedNavigationUsesNativeHostCallbacksAndDestinations() throws {
    let fixture = repository.appendingPathComponent("Fixtures/navigation-typed")
    let input = try String(contentsOf: fixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    let mapping = try Mapping.load(data: Data(try String(contentsOf: fixture.appendingPathComponent("refract.json"), encoding: .utf8).utf8),
                                  file: "refract.json", resourceBaseURL: fixture)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input), mapping: mapping)
    #expect(unit.diagnostics.isEmpty)
    #expect(unit.module.screens.count == 2)
    guard case let .navigationStack(stack, _)? = unit.module.screens.last?.body else {
        Issue.record("Expected the source NavigationStack")
        return
    }
    #expect(stack.rootName == "NavigationScreen")
    #expect(stack.models.map(\.propertyName) == ["model"])
    #expect(stack.destinations.map(\.caseName) == ["detail", "native"])

    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("onPathNavigate: (Route) -> Unit"))
    #expect(kotlin.contains("public fun NavigationScreenDestinations("))
    #expect(kotlin.contains("DetailScreen(model = model, modifier = modifier)"))
    #expect(kotlin.contains("NativeDetail()"))
    #expect(!kotlin.contains("NavHost("))
    #expect(!kotlin.contains("NavController"))
    #expect(!kotlin.contains("Map<String"))

    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("@Event onPathNavigate: (destination: Route) => void"))
    #expect(ark.contains("export struct NavigationScreenDestinations"))
    #expect(ark.contains("DetailScreen({ model: this.model })"))
    #expect(!ark.contains("NavPathStack"))
    #expect(!ark.contains("@Entry"))
}

@Test(arguments: [
    ("enum Route: Hashable { case detail(String) }", "RFNAV002"),
    ("enum Route { case detail }", "RFNAV002"),
])
func navigationRejectsUntypedDestinationValues(_ declaration: String, _ code: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    \(declaration)
    protocol DetailModel: RefractModel { var title: String { get } }
    struct DetailScreen: View {
        let model: DetailModel
        var body: some View { Text(model.title) }
    }
    struct NavigationScreen: View {
        let model: DetailModel
        @State private var path: [Route] = []
        var body: some View {
            NavigationStack(path: $path) {
                VStack { NavigationLink("navigation.open", value: .detail) }
                    .navigationDestination(for: Route.self) { route in
                        switch route { case .detail: DetailScreen(model: model) }
                    }
            }
        }
    }
    """))
    #expect(unit.diagnostics.contains(where: { $0.code == code }))
}

@Test func navigationRejectsIncompleteDestinations() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum Route: Hashable { case detail; case native }
    struct NavigationScreen: View {
        @State private var path: [Route] = []
        var body: some View {
            NavigationStack(path: $path) {
                VStack { NavigationLink("navigation.open", value: .detail) }
                    .navigationDestination(for: Route.self) { route in
                        switch route { case .detail: Text(verbatim: "detail") }
                    }
            }
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code).contains("RFNAV003"))
    #expect(unit.module.screens.isEmpty)
}

@Test func navigationRejectsDynamicLinksAndUnknownDestinations() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum Route: Hashable { case detail }
    struct NavigationScreen: View {
        @State private var path: [Route] = []
        var body: some View {
            NavigationStack(path: $path) {
                VStack { NavigationLink("navigation.open", value: path[0]) }
                    .navigationDestination(for: Route.self) { route in
                        switch route { case .detail: UnknownScreen() }
                    }
            }
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code).allSatisfy { $0.hasPrefix("RFNAV") })
    #expect(unit.diagnostics.contains(where: { $0.code == "RFNAV001" }))
    #expect(unit.module.screens.isEmpty)
}
