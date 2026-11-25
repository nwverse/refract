import Foundation
import Testing
import RefractFrontend
@testable import RefractCompose
import RefractIR
import RefractMapping

@Test func composeEmitsNativeComposable() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Hello", body: .text(Expression(.stringLiteral("Hello")), modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module)
    #expect(output.contains("DO NOT EDIT"))
    #expect(output.contains("import androidx.compose.runtime.Composable"))
    #expect(output.contains("import androidx.compose.material3.Text"))
    #expect(output.contains("@Composable"))
    #expect(output.contains("public fun Hello(modifier: Modifier = Modifier)"))
    #expect(output.contains("text = \"Hello\""))
    #expect(!output.contains("import refract."))
}

@Test func composeEmitsVStackWithChildren() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Hello", body: .stack(axis: .vertical, children: [
            .text(Expression(.stringLiteral("Hello")), modifiers: [], location: nil),
            .text(Expression(.stringLiteral("World")), modifiers: [], location: nil),
        ], modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module)
    #expect(output.contains("import androidx.compose.foundation.layout.Column"))
    #expect(output.contains("Column(modifier = modifier)"))
    #expect(output.contains("Text(text = \"Hello\")"))
    #expect(output.contains("Text(text = \"World\")"))
}

@Test func composeEmitsHStackAsRow() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Row", body: .stack(axis: .horizontal, children: [
            .text(Expression(.stringLiteral("Left")), modifiers: [], location: nil),
        ], modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module)
    #expect(output.contains("import androidx.compose.foundation.layout.Row"))
    #expect(output.contains("Row(modifier = modifier)"))
}

@Test func composeEmitsZStackAsBox() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Overlay", body: .stack(axis: .depth, children: [
            .text(Expression(.stringLiteral("Front")), modifiers: [], location: nil),
        ], modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module)
    #expect(output.contains("import androidx.compose.foundation.layout.Box"))
    #expect(output.contains("Box(modifier = modifier)"))
}

@Test func composeEmitsButtonWithEmptyAction() throws {
    let label = ViewNode.text(Expression(.stringLiteral("Go")), modifiers: [], location: nil)
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Screen", body: .button(label: label, action: nil, modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module)
    #expect(output.contains("import androidx.compose.material3.Button"))
    #expect(output.contains("Button(onClick = { }"))
}

@Test func composeEmitsPaddingModifier() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Screen", body: .stack(axis: .vertical, children: [
            .text(Expression(.stringLiteral("Hi")),
                  modifiers: [Modifier(name: "padding")],
                  location: nil),
        ], modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module)
    #expect(output.contains("import androidx.compose.foundation.layout.padding"))
    #expect(output.contains("import androidx.compose.ui.unit.dp"))
    #expect(output.contains(".padding(all = 16.dp)"))
}

@Test func composeEmitsLocalState() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Counter",
               states: [.state(name: "count", type: .int, initialValue: Expression(.numberLiteral("0")), location: nil)],
               body: .text(Expression(.reference("count")), modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module)
    #expect(output.contains("import androidx.compose.runtime.remember"))
    #expect(output.contains("import androidx.compose.runtime.mutableStateOf"))
    #expect(output.contains("var count by remember { mutableStateOf(0) }"))
}

@Test func composePreservesDoubleStateFromIntegerLiteral() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Progress",
               states: [.state(name: "progress", type: .double, initialValue: Expression(.numberLiteral("0")), location: nil)],
               body: .text(Expression(.reference("progress")), modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module)
    #expect(output.contains("var progress by remember { mutableStateOf<Double>(0) }"))
}

@Test func composeEmitsBindingParameters() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "EnabledRow",
               states: [.binding(name: "isEnabled", type: .bool, location: nil)],
               body: .text(Expression(.reference("isEnabled")), modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module)
    #expect(output.contains("isEnabled: Boolean,"))
    #expect(output.contains("onIsEnabledChange: (Boolean) -> Unit,"))
}

@Test func composeEmitsModelParameter() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Settings",
               states: [.model(ModelReference(propertyName: "model", protocolName: "SettingsModel"), location: nil)],
               body: .text(Expression(.stringLiteral("Hi")), modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module)
    #expect(output.contains("model: SettingsModel,"))
}

@Test func composeRejectsUnknownModifier() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Screen", body: .text(Expression(.stringLiteral("Hi")),
                                            modifiers: [Modifier(name: "nonexistent")],
                                            location: nil)),
    ])
    #expect(throws: Diagnostic.self) {
        _ = try ComposeBackend().generate(module: module)
    }
}

@Test func composeDoesNotDuplicateMappedNativeImports() throws {
    let android = PlatformMapping(
        imports: [NativeImport(module: "example.components.MapView", symbols: ["MapView"])]
    )
    let mapping = Mapping(android: android)
    let plain = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Plain", body: .text(Expression(.stringLiteral("Hello")), modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: plain, mapping: mapping)
    #expect(output.components(separatedBy: "import example.components.MapView\n").count == 2)
}

@Test func composeRejectsNativeWithoutMapping() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Screen", body: .native(NativeComponent(name: "MapView"), location: nil)),
    ])
    #expect(throws: Diagnostic.self) {
        _ = try ComposeBackend().generate(module: module)
    }
}

@Test func composeEmitsCompleteLocalizedToggleTitle() throws {
    let android = PlatformMapping(output: Output(directory: "generated", packageName: "refract.generated"),
                                 resources: Resources(className: "refract.generated.R",
                                                      strings: ["settings.enabled": "settings_enabled"]))
    let mapping = Mapping(android: android)
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "ToggleRow", body: .toggle(title: Expression(.stringKey("settings.enabled")),
            value: Expression(.valueProperty(.binding("isEnabled"))), modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module, mapping: mapping)
    #expect(output.contains("import androidx.compose.material3.Text\n"))
    #expect(output.contains("Text(text = stringResource(R.string.settings_enabled))"))
    #expect(output.contains("Switch("))
}

@Test func composeKeepsExternalResourceClassQualified() throws {
    let android = PlatformMapping(output: Output(directory: "generated", packageName: "refract.generated"),
                                 resources: Resources(className: "example.app.R",
                                                      strings: ["settings.enabled": "settings_enabled"]))
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "ToggleRow", body: .toggle(title: Expression(.stringKey("settings.enabled")),
            value: Expression(.valueProperty(.binding("isEnabled"))), modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module, mapping: Mapping(android: android))
    #expect(output.contains("Text(text = stringResource(example.app.R.string.settings_enabled))"))
}

// Regression coverage for #406: frontend graph linking replaces a qualified link's placeholder with the exact
// operation before serialization. Golden source evidence does not bless ArkUI's separate forwarding defect (#413).
@Test func composePreservesCustomDeepNavigationPathCallback() throws {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/RefractComposeTests/Fixtures/navigation-custom-path")
    let input = try String(contentsOf: directory.appendingPathComponent("Input.swift"), encoding: .utf8)
    let mapping = try Mapping.load(contentsOf: directory.appendingPathComponent("refract.json"))
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input), mapping: mapping)
    #expect(unit.diagnostics.isEmpty)
    let detail = try #require(unit.module.screens.first { $0.name == "DeepDetailScreen" })
    var linkPathNames: [String] = []
    func collectLinkPaths(_ node: ViewNode) {
        if case let .navigationLink(_, pathName, _, _, _) = node { linkPathNames.append(pathName) }
        node.children.forEach(collectLinkPaths)
    }
    collectLinkPaths(detail.body)
    #expect(detail.navigation == NavigationOperation(pathName: "routePath", enumName: "DeepRoute"))
    #expect(linkPathNames == ["routePath"])
    let decoded = try JSONDecoder().decode(Module.self, from: JSONEncoder().encode(unit.module))
    #expect(decoded == unit.module)
    let output = try ComposeBackend().generate(module: decoded, mapping: mapping)
    let expected = try String(contentsOf: directory.appendingPathComponent("Expected.kt"), encoding: .utf8)
    #expect(output == expected)
    #expect(output.contains("onRoutePathNavigate: (DeepRoute) -> Unit"))
    #expect(output.contains("onRoutePathNavigate(DeepRoute.editor)"))
    #expect(output.contains("DeepDetailScreen(model = model, onRoutePathNavigate = onRoutePathNavigate, modifier = modifier)"))
    #expect(!output.contains("onPathNavigate"))
}

@Test(arguments: ["destination", "root"])
func composeRejectsMismatchedPublicNavigationLinkPath(inputKind: String) throws {
    let link = ViewNode.navigationLink(
        title: Expression(.stringLiteral("Open"), type: .string, location: nil),
        pathName: "path", enumName: "Route", destination: "editor", location: nil)
    let screen = inputKind == "destination"
        ? Screen(name: "Detail", navigation: NavigationOperation(pathName: "routePath", enumName: "Route"), body: link)
        : Screen(name: "Root", body: .navigationStack(NavigationStackNode(
            pathName: "routePath", rootName: "Root", enumName: "Route", content: [link],
            destinations: [NavigationDestination(caseName: "editor", viewName: "Editor")]), location: nil))
    var module = Module(sourceFile: "Input.swift", screens: [screen],
                        nativeDeclarations: [NativeDeclaration(name: "Editor", parameters: [])],
                        enums: [EnumDeclaration(name: "Route", cases: ["editor"], isNavigationDestination: true)])
    if inputKind == "root" {
        module = try JSONDecoder().decode(Module.self, from: JSONEncoder().encode(module))
    }
    do {
        _ = try ComposeBackend().generate(module: module)
        Issue.record("Expected \(inputKind) IR with a mismatched path to fail")
    } catch let diagnostic as Diagnostic {
        #expect(diagnostic.code == "RFNAV003")
    }
}

@Test(arguments: ["manual JSON", "decoded JSON"])
func composeRejectsMismatchedPublicNavigationLinkWithObsoleteMarker(inputKind: String) throws {
    let link = ViewNode.navigationLink(
        title: Expression(.stringLiteral("Open"), type: .string, location: nil),
        pathName: "path", enumName: "Route", destination: "editor", location: nil)
    let screen = Screen(
        name: "Detail",
        navigation: NavigationOperation(pathName: "routePath", enumName: "Route"),
        body: link)
    let module = Module(sourceFile: "Input.swift", screens: [screen],
                        enums: [EnumDeclaration(name: "Route", cases: ["editor"], isNavigationDestination: true)])
    let data = try JSONEncoder().encode(module)
    if inputKind == "decoded JSON" {
        _ = try JSONDecoder().decode(Module.self, from: data)
    }
    var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    var screens = try #require(object["screens"] as? [[String: Any]])
    var navigation = try #require(screens[0]["navigation"] as? [String: Any])
    // This is the marker-present counterexample from review 6060689709. It is not trusted provenance.
    navigation["allowsEnclosingGraphPathPlaceholder"] = true
    screens[0]["navigation"] = navigation
    object["screens"] = screens
    let decoded = try JSONDecoder().decode(Module.self, from: JSONSerialization.data(withJSONObject: object))
    do {
        _ = try ComposeBackend().generate(module: decoded)
        Issue.record("Expected \(inputKind) marker-present IR with a mismatched path to fail")
    } catch let diagnostic as Diagnostic {
        #expect(diagnostic.code == "RFNAV003")
    }
}

@Test func composeDeterministicOutput() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Hello", body: .stack(axis: .vertical, children: [
            .text(Expression(.stringLiteral("Hello")), modifiers: [Modifier(name: "padding")], location: nil),
            .button(label: .text(Expression(.stringLiteral("Go")), modifiers: [], location: nil),
                    action: nil, modifiers: [], location: nil),
        ], modifiers: [], location: nil)),
    ])
    let first = try ComposeBackend().generate(module: module)
    let second = try ComposeBackend().generate(module: module)
    #expect(first == second)
}
