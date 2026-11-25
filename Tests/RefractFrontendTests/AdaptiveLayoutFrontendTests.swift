import Foundation
import RefractArkUI
import RefractCompose
import RefractFrontend
import RefractIR
import RefractMapping
import Testing

private let adaptiveRepository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Test func adaptiveSettingsUsesNativeWidthClassAndSharedState() throws {
    let fixture = adaptiveRepository.appendingPathComponent("Fixtures/adaptive-window-size")
    let mapping = try Mapping.load(contentsOf: fixture.appendingPathComponent("refract.json"))
    let input = try String(contentsOf: fixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input), mapping: mapping)
    #expect(unit.diagnostics.isEmpty)
    let screen = try #require(unit.module.screens.first { $0.name == "AdaptiveSettingsScreen" })
    #expect(screen.parameters.map(\.name) == ["widthSizeClass"])
    #expect(screen.states.count == 3)
    guard case let .switchExpression(subject, enumName, cases, _) = screen.body else {
        Issue.record("Expected the shared enum/switch IR")
        return
    }
    #expect(subject == Expression(.reference("widthSizeClass"), location: subject.location))
    #expect(enumName == "WidthSizeClass")
    #expect(cases.map(\.name) == ["compact", "expanded"])

    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("widthSizeClass: WindowWidthSizeClass"))
    #expect(kotlin.contains("if (widthSizeClass == WindowWidthSizeClass.Compact)"))
    #expect(kotlin.contains("displayName: String"))
    #expect(kotlin.contains("onDisplayNameChange: (String) -> Unit"))
    #expect(!kotlin.contains("public enum class WidthSizeClass"))
    #expect(!kotlin.contains("calculateWindowSizeClass"))
    #expect(!kotlin.contains("NavHost("))
    #expect(kotlin.components(separatedBy: "widthSizeClass: WindowWidthSizeClass").count == 2)

    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("export enum WidthSizeClass"))
    #expect(ark.contains("@Param @Require public var widthSizeClass: WidthSizeClass"))
    #expect(ark.contains("@Require @Param displayName: string;"))
    #expect(ark.contains("@Event onDisplayNameChange: (value: string) => void"))
    #expect(ark.contains("this.widthSizeClass === WidthSizeClass.expanded"))
    #expect(!ark.contains("GridRow("))
    #expect(!ark.contains("NavPathStack"))
}

@Test func adaptiveWidthClassIsNotAnOrdinaryEnumOrTextValue() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum WidthSizeClass {
        case compact
        case expanded
    }
    struct Screen: View {
        let widthSizeClass: WidthSizeClass
        var body: some View {
            Text(widthSizeClass)
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code).contains("RFSEM002"))
}

@Test(arguments: [
    "@State private var widthSizeClass: WidthSizeClass = .compact",
    "@Binding var widthSizeClass: WidthSizeClass",
])
func widthClassRejectsWrongOwnershipWithAdaptiveDiagnostic(_ declaration: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum WidthSizeClass { case compact; case expanded }
    struct InvalidAdaptiveOwnership: View {
        \(declaration)
        var body: some View {
            switch widthSizeClass {
            case .compact: Text(verbatim: "Compact")
            case .expanded: Text(verbatim: "Expanded")
            }
        }
    }
    """))
    #expect(unit.hasErrors)
    #expect(unit.module.screens.isEmpty)
    #expect(unit.diagnostics.map(\.code) == ["RFADAPT001"])
}

@Test func wrongWidthClassOwnershipRetainsOtherStateDiagnostics() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum WidthSizeClass { case compact; case expanded }
    struct InvalidAdaptiveOwnership: View {
        @Binding var widthSizeClass: WidthSizeClass
        @State private var count: Int
        var body: some View {
            switch widthSizeClass {
            case .compact: Text(verbatim: "Compact")
            case .expanded: Text(verbatim: "Expanded")
            }
        }
    }
    """))
    #expect(unit.hasErrors)
    #expect(unit.module.screens.isEmpty)
    #expect(unit.diagnostics.map(\.code) == ["RFADAPT001", "state.invalid_declaration"])
}

@Test func widthClassCannotOwnTheNativeNavigationPath() throws {
    let fixture = adaptiveRepository.appendingPathComponent("Fixtures/adaptive-reject-navigation")
    let input = try String(contentsOf: fixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input))
    #expect(unit.diagnostics.map(\.code).contains("RFADAPT003"))
}
