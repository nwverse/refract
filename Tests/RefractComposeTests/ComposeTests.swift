import Testing
@testable import RefractCompose
import RefractIR

@Test func composeEmitsNativeComposable() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Hello", body: .text(Expression(.stringLiteral("Hello")), modifiers: [], location: nil)),
    ])
    let output = try ComposeBackend().generate(module: module)
    #expect(output.contains("@Composable\npublic fun Hello()"))
    #expect(output.contains("Text(text = \"Hello\")"))
    #expect(output.contains("DO NOT EDIT"))
}
