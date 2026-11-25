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
    let fixture = repository.appendingPathComponent("Fixtures/navigation-native-destination")
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
    #expect(stack.rootName == "EscapeScreen")
    #expect(stack.models.map(\.propertyName) == ["model"])
    #expect(stack.destinations.map(\.caseName) == ["detail", "native"])

    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("onPathNavigate: (EscapeRoute) -> Unit"))
    #expect(kotlin.contains("public fun EscapeScreenDestinations("))
    #expect(kotlin.contains("EscapeDetailScreen(model = model, modifier = modifier)"))
    #expect(kotlin.contains("NativeDetail()"))
    #expect(!kotlin.contains("NavHost("))
    #expect(!kotlin.contains("NavController"))
    #expect(!kotlin.contains("Map<String"))

    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("@Event onPathNavigate: (destination: EscapeRoute) => void"))
    #expect(ark.contains("export struct EscapeScreenDestinations"))
    #expect(ark.contains("EscapeDetailScreen({ model: this.model })"))
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

@Test(arguments: [
    "let count: Int",
    "let other: DetailModel",
    "@Binding var count: Int",
])
func navigationRejectsUnforwardedDestinationInputs(_ input: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum Route: Hashable { case detail }
    protocol DetailModel: RefractModel { var title: String { get } }
    struct DetailScreen: View {
        let model: DetailModel
        \(input)
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
    #expect(unit.diagnostics.contains {
        $0.code == "RFNAV003" && $0.message.contains("one declared model input")
    })
    #expect(unit.module.screens.contains { $0.name == "NavigationScreen" } == false)
}

@Test func navigationRejectsDestinationOwnedPathWithoutAChildLink() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum Route: Hashable { case detail }
    protocol DetailModel: RefractModel { var title: String { get } }
    struct DetailScreen: View {
        let model: DetailModel
        @State private var childPath: [Route] = []
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
    #expect(unit.diagnostics.contains {
        $0.code == "RFNAV003" &&
            $0.message.contains("childPath") &&
            $0.suggestion?.contains("NavigationLink") == true
    })
    #expect(!unit.diagnostics.contains { $0.code == "RFNAV001" })
}

@Test(arguments: [
    ("@State private var count: Int = 0", false),
    ("@State private var form = refractForm {\n        Field(\"email\", initial: \"\", rules: .nonEmpty)\n    }", true),
])
func navigationAllowsDestinationOwnedLocalState(_ state: String, _ hasForm: Bool) throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum Route: Hashable { case detail }
    protocol DetailModel: RefractModel {
        var title: String { get }
        @refractAsync func submit(email: String)
    }
    struct DetailScreen: View {
        let model: DetailModel
        \(state)
        var body: some View { \(hasForm ? "Form { TextField(\"settings.email\", text: $form.email)\n            Button(\"settings.submit\") { form.submit(model.submit) }\n        } (form: $form)" : "Text(model.title)") }
    }
    struct NavigationScreen: View {
        let model: DetailModel
        @State private var path: [Route] = []
        var body: some View {
            NavigationStack(path: $path) {
                VStack { NavigationLink("settings.submit", value: .detail) }
                    .navigationDestination(for: Route.self) { route in
                        switch route { case .detail: DetailScreen(model: model) }
                    }
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .navigationStack(stack, _)? = unit.module.screens.last?.body else {
        Issue.record("Expected a navigation stack with a stateful destination")
        return
    }
    #expect(stack.destinations.map(\.caseName) == ["detail"])

    let fixture = repository.appendingPathComponent("Fixtures/form-validation")
    let mapping = try Mapping.load(contentsOf: fixture.appendingPathComponent("refract.json"))
    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("DetailScreen(model = model, modifier = modifier)"))
    #expect(kotlin.contains(hasForm ? "var formEmail by remember { mutableStateOf(\"\") }" : "remember { mutableStateOf(0) }"))
    #expect(!kotlin.contains("onChildPathNavigate"))

    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("DetailScreen({ model: this.model })"))
    #expect(ark.contains(hasForm ? "@Local private formEmail: string = '';" : "@Local private count: number = 0;"))
    #expect(!ark.contains("onChildPathNavigate"))
}

@Test func manuallyConstructedNavigationCannotEmitAnInvalidDestinationModel() {
    let model = ModelReference(propertyName: "model", protocolName: "DetailModel")
    let destination = NavigationDestination(caseName: "detail", viewName: "MissingScreen",
                                            model: .init(label: "model", expression: "model"))
    let stack = NavigationStackNode(pathName: "path", rootName: "Root", enumName: "Route", content: [],
                                    destinations: [destination], models: [model])
    let screen = Screen(name: "Root", states: [.model(model, location: nil), .navigationPath(name: "path", enumName: "Route", location: nil)],
                        body: .navigationStack(stack, location: nil))
    let module = Module(sourceFile: "Input.swift", screens: [screen],
                        models: [ModelProtocol(name: "DetailModel")],
                        enums: [EnumDeclaration(name: "Route", cases: ["detail"], isNavigationDestination: true)])
    #expect(throws: Diagnostic.self) { _ = try ComposeBackend().generate(module: module) }
    #expect(throws: Diagnostic.self) { _ = try ArkUIBackend().generate(module: module) }
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
