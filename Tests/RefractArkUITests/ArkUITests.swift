import Testing
@testable import RefractArkUI
import RefractIR

@Test func arkUIEmitsNativeComponent() throws {
    let module = Module(sourceFile: "Input.swift", screens: [
        Screen(name: "Hello", body: .text(Expression(.stringLiteral("Hello")), modifiers: [], location: nil)),
    ])
    let output = try ArkUIBackend().generate(module: module)
    #expect(output.contains("@Component\nexport struct Hello"))
    #expect(output.contains("Text(\"Hello\")"))
    #expect(output.contains("DO NOT EDIT"))
}
