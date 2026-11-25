import Foundation
import Testing
@testable import RefractIR

@Test func diagnosticsHaveStableCodesAndLocations() {
    let diagnostic = Diagnostic(code: "unsupportedView", message: "Image is not supported.",
                                suggestion: "Text", location: SourceLocation(file: "Input.swift", line: 4, column: 9))
    #expect(diagnostic.rendered == "Input.swift:4:9: error [unsupportedView]: Image is not supported. Suggestion: Text")
}

@Test func typedNativeAndModelReferencesRoundTrip() throws {
    let screen = Screen(name: "Settings", states: [
        .state(name: "enabled", type: .bool, initialValue: Expression(.boolLiteral(true)), location: nil),
        .binding(name: "title", type: .string, location: nil),
        .model(ModelReference(propertyName: "model", protocolName: "SettingsModel"), location: nil),
    ], modals: [ModalPresentation(kind: .sheet, stateName: "enabled", isBinding: false)],
       navigation: NavigationOperation(enumName: "Route"),
       body: .native(NativeComponent(name: "Map", arguments: [
        NativeArgument(label: "title", expression: Expression(.stringKey("map.title")), type: .string),
    ]), location: nil))
    let module = Module(sourceFile: "Input.swift", screens: [screen])
    let decoded = try JSONDecoder().decode(Module.self, from: JSONEncoder().encode(module))
    #expect(decoded == module)
}

@Test func obsoleteNavigationPlaceholderMarkerDecodesWithoutBecomingBinding() throws {
    let operation = try JSONDecoder().decode(NavigationOperation.self, from: Data("""
    {"pathName":"routePath","enumName":"Route","allowsEnclosingGraphPathPlaceholder":true}
    """.utf8))
    #expect(operation == NavigationOperation(pathName: "routePath", enumName: "Route"))
    let serialized = try JSONSerialization.jsonObject(with: JSONEncoder().encode(operation))
    let object = try #require(serialized as? [String: Any])
    #expect(object["allowsEnclosingGraphPathPlaceholder"] == nil)
}
