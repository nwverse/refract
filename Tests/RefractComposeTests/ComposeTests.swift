import Testing
@testable import RefractCompose
import RefractIR

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
    #expect(output.contains("verticalArrangement = Arrangement.spacedBy(8.dp)"))
    #expect(output.contains("horizontalAlignment = Alignment.CenterHorizontally"))
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

@Test func composeRejectsNativeWithoutMapping() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Screen", body: .native(NativeComponent(name: "MapView"), location: nil)),
    ])
    #expect(throws: Diagnostic.self) {
        _ = try ComposeBackend().generate(module: module)
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
