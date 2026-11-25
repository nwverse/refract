import Foundation
import RefractArkUI
import RefractFrontend
import RefractIR
import RefractMapping
import Testing

private let customNavigationFixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("Fixtures/navigation-custom-path")

private func parsedCustomNavigationFixture() throws -> (Module, Mapping) {
    let input = try String(contentsOf: customNavigationFixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    let mapping = try Mapping.load(data: Data(contentsOf: customNavigationFixture.appendingPathComponent("refract.json")),
                                  file: "refract.json", resourceBaseURL: customNavigationFixture)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input), mapping: mapping)
    #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
    #expect(unit.module.screens.first(where: { $0.name == "DeepDetailScreen" })?.navigation ==
        NavigationOperation(pathName: "routePath", enumName: "DeepRoute"))
    return (unit.module, mapping)
}

@Test func arkUICustomPathMatchesEveryDeclarationUseAndForward() throws {
    let (module, mapping) = try parsedCustomNavigationFixture()
    let output = try ArkUIBackend().generate(module: module, mapping: mapping)
    let expected = try String(contentsOf: customNavigationFixture.appendingPathComponent("Expected.ets"), encoding: .utf8)
    #expect(output == expected, Comment(rawValue: output))
    #expect(!output.contains("onPathNavigate"))
    #expect(!output.contains("NavPathStack"))
    #expect(!output.contains("AppStorage"))
}

@Test func arkUIDefaultPathGenerationRemainsStable() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/navigation-deep-restoration")
    let input = try String(contentsOf: fixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    let mapping = try Mapping.load(data: Data(contentsOf: fixture.appendingPathComponent("refract.json")),
                                  file: "refract.json", resourceBaseURL: fixture)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input), mapping: mapping)
    #expect(unit.diagnostics.isEmpty, Comment(rawValue: unit.diagnostics.map(\.rendered).joined(separator: "\n")))
    let output = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    let expected = try String(contentsOf: fixture.appendingPathComponent("Expected.ets"), encoding: .utf8)
    #expect(output == expected)
}

@Test(arguments: [
    (name: "missing", operation: NavigationOperation?.none),
    (name: "mismatched", operation: NavigationOperation?.some(NavigationOperation(pathName: "otherPath", enumName: "DeepRoute"))),
])
func arkUIQualifiedLinkRequiresItsCheckedEnclosingOperation(_ name: String, _ operation: NavigationOperation?) throws {
    var (module, mapping) = try parsedCustomNavigationFixture()
    let detail = try #require(module.screens.first(where: { $0.name == "DeepDetailScreen" }))
    let replacement = Screen(name: detail.name, parameters: detail.parameters, states: detail.states,
                             modals: detail.modals, navigation: operation, body: detail.body,
                             nativeValues: detail.nativeValues, lifecycle: detail.lifecycle, location: detail.location)
    module = Module(sourceFile: module.sourceFile,
                    screens: module.screens.map { $0.name == detail.name ? replacement : $0 },
                    nativeDeclarations: module.nativeDeclarations, models: module.models,
                    itemTypes: module.itemTypes, enums: module.enums, nativeHosts: module.nativeHosts)

    let diagnostic = #expect(throws: Diagnostic.self) {
        try ArkUIBackend().generate(module: module, mapping: mapping)
    }
    #expect(diagnostic?.code == "RFNAV003", Comment(rawValue: name))
    #expect(diagnostic?.message.contains("navigation operation") == true, Comment(rawValue: name))
    #expect(diagnostic?.suggestion?.isEmpty == false, Comment(rawValue: diagnostic?.rendered ?? name))
}

private func frontendNavigationLinks(in node: ViewNode) -> [(path: String, enumName: String)] {
    if case let .navigationLink(_, pathName, enumName, _, _) = node { return [(pathName, enumName)] }
    return node.children.flatMap(frontendNavigationLinks)
}

@Test func frontendResolvesCustomGraphOwnershipBeforeBackendEmission() throws {
    let (module, mapping) = try parsedCustomNavigationFixture()
    let decoded = try JSONDecoder().decode(Module.self, from: JSONEncoder().encode(module))
    let detail = try #require(decoded.screens.first(where: { $0.name == "DeepDetailScreen" }))
    #expect(frontendNavigationLinks(in: detail.body).map(\.path) == ["routePath"])
    let root = try #require(decoded.screens.first(where: { $0.name == "DeepNavigationScreen" }))
    #expect(frontendNavigationLinks(in: root.body).map(\.path) == ["routePath"])

    let output = try ArkUIBackend().generate(module: decoded, mapping: mapping)
    let expected = try String(contentsOf: customNavigationFixture.appendingPathComponent("Expected.ets"), encoding: .utf8)
    #expect(output == expected)
}

@Test(arguments: [false, true])
func arkUIRejectsRegisteredDecodedOrManualLinkPathMismatch(decoded: Bool) throws {
    var (module, mapping) = try parsedCustomNavigationFixture()
    let detail = try #require(module.screens.first(where: { $0.name == "DeepDetailScreen" }))
    let link = ViewNode.navigationLink(title: Expression(.stringLiteral("Open"), type: .string, location: nil),
                                       pathName: "path", enumName: "DeepRoute", destination: "editor", location: nil)
    let replacement = Screen(name: detail.name, parameters: detail.parameters, states: detail.states,
                             modals: detail.modals, navigation: detail.navigation, body: link,
                             nativeValues: detail.nativeValues, lifecycle: detail.lifecycle, location: detail.location)
    module = Module(sourceFile: module.sourceFile,
                    screens: module.screens.map { $0.name == detail.name ? replacement : $0 },
                    nativeDeclarations: module.nativeDeclarations, models: module.models,
                    itemTypes: module.itemTypes, enums: module.enums, nativeHosts: module.nativeHosts)
    if decoded {
        module = try JSONDecoder().decode(Module.self, from: JSONEncoder().encode(module))
    }

    let diagnostic = #expect(throws: Diagnostic.self) {
        try ArkUIBackend().generate(module: module, mapping: mapping)
    }
    #expect(diagnostic?.code == "RFNAV003")
    #expect(diagnostic?.message.contains("enclosing navigation operation") == true)
}
