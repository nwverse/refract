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

// Regression: an earlier typed/model dispatch bypassed the reserved-width check.
// Both wrong-ownership forms must yield RFADAPT001, never RFNAV402 from a sibling.
@Test(arguments: [
    "@State private var widthSizeClass: WidthSizeClass = .compact",
    "@Binding var widthSizeClass: WidthSizeClass",
])
func wrongWidthClassOwnershipWithModelSiblingStillReportsAdaptiveDiagnostic(_ declaration: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum WidthSizeClass { case compact; case expanded }
    protocol SettingsModel: RefractModel { var title: String { get } }
    struct InvalidAdaptiveOwnership: View {
        \(declaration)
        let model: SettingsModel
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

@Test(arguments: [
    "@State private var widthSizeClass: WidthSizeClass = .compact",
    "@Binding var widthSizeClass: WidthSizeClass",
])
func wrongWidthClassOwnershipWithTypedInputSiblingStillReportsAdaptiveDiagnostic(_ declaration: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum WidthSizeClass { case compact; case expanded }
    struct InvalidAdaptiveOwnership: View {
        \(declaration)
        let title: String
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

@Test(arguments: [
    "@State private var widthSizeClass: WidthSizeClass = .compact",
    "@Binding var widthSizeClass: WidthSizeClass",
])
func wrongWidthClassOwnershipWithNativeHostSiblingStillReportsAdaptiveDiagnostic(_ declaration: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum WidthSizeClass { case compact; case expanded }
    protocol Host: RefractNotificationHost {
        func present(_ id: String, revision: Int) -> Bool
        func cancel(_ id: String, revision: Int)
        func confirm(_ id: String, revision: Int)
    }
    struct InvalidAdaptiveOwnership: View {
        \(declaration)
        let host: Host
        @RefractNativeValue var event: RefractNotificationEvent
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
    #expect(unit.diagnostics.map(\.code).contains("RFADAPT001"))
}

// Regression: an invalid enum tab sibling must not hide the next sibling's
// state.invalid_declaration when the reserved width input is already rejected.
@Test(arguments: [
    "@State private var widthSizeClass: WidthSizeClass = .compact",
    "@Binding var widthSizeClass: WidthSizeClass",
])
func wrongWidthClassOwnershipPreservesTabAndScalarStateDiagnostics(_ declaration: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum WidthSizeClass { case compact; case expanded }
    enum HomeTab: Hashable { case home }
    struct InvalidAdaptiveOwnership: View {
        \(declaration)
        @Binding var tab: HomeTab
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
    #expect(unit.diagnostics.map(\.code) == ["RFADAPT001", "RFNAV402", "state.invalid_declaration"])
}

// Regression: an invalid form must not hide the next sibling's state diagnostic
// when the reserved width input is already rejected in collect-all mode.
@Test(arguments: [
    "@State private var widthSizeClass: WidthSizeClass = .compact",
    "@Binding var widthSizeClass: WidthSizeClass",
])
func wrongWidthClassOwnershipPreservesFormAndScalarStateDiagnostics(_ declaration: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum WidthSizeClass { case compact; case expanded }
    struct InvalidAdaptiveOwnership: View {
        \(declaration)
        @State private var form = refractForm { Field("email", rules: .nonEmpty) }
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
    #expect(unit.diagnostics.map(\.code) == ["RFADAPT001", "RFFORM001", "state.invalid_declaration"])
}

// Positive control: the same scalar sibling without a form retains its own diagnostic.
@Test(arguments: [
    "@State private var widthSizeClass: WidthSizeClass = .compact",
    "@Binding var widthSizeClass: WidthSizeClass",
])
func wrongWidthClassOwnershipPreservesScalarStateDiagnosticWithoutForm(_ declaration: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum WidthSizeClass { case compact; case expanded }
    struct InvalidAdaptiveOwnership: View {
        \(declaration)
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

// Positive control: valid let widthSizeClass with a form, scalar state and model
// retains the ordinary screen without changing the collect-only error path.
@Test func validWidthClassWithFormScalarStateAndModelProducesScreen() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum WidthSizeClass { case compact; case expanded }
    protocol SettingsModel: RefractModel {
        @refractAsync func save(email: String)
    }
    struct ValidAdaptiveScreen: View {
        let widthSizeClass: WidthSizeClass
        let model: SettingsModel
        @State private var form = refractForm {
            Field("email", initial: "", rules: .nonEmpty)
        }
        @State private var count: Int = 0
        var body: some View {
            switch widthSizeClass {
            case .compact: Text(verbatim: "Compact \\(count)")
            case .expanded:
                Form {
                    TextField("settings.email", text: $form.email)
                    Button("settings.submit") { form.submit(model.save) }
                } (form: $form)
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let screen = try #require(unit.module.screens.first { $0.name == "ValidAdaptiveScreen" })
    #expect(screen.parameters.map(\.name) == ["widthSizeClass"])
    let formNames = screen.states.compactMap { state -> String? in
        guard case let .form(_, declaration, _) = state else { return nil }
        return declaration.name
    }
    #expect(formNames == ["form"])
    #expect(screen.states.count == 3)
}

// Positive control: valid let widthSizeClass with model and bindings keeps working.
@Test func validWidthClassWithModelAndBindingsProducesScreen() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum WidthSizeClass { case compact; case expanded }
    protocol SettingsModel: RefractModel { var title: String { get } }
    struct ValidAdaptiveScreen: View {
        let model: SettingsModel
        let widthSizeClass: WidthSizeClass
        @Binding var displayName: String
        var body: some View {
            switch widthSizeClass {
            case .compact: Text(model.title)
            case .expanded: Text(displayName)
            }
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    let screen = unit.module.screens.first { $0.name == "ValidAdaptiveScreen" }
    #expect(screen != nil)
    #expect(screen?.parameters.map(\.name) == ["widthSizeClass"])
}

@Test func widthClassCannotOwnTheNativeNavigationPath() throws {
    let fixture = adaptiveRepository.appendingPathComponent("Fixtures/adaptive-reject-navigation")
    let input = try String(contentsOf: fixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input))
    #expect(unit.diagnostics.map(\.code).contains("RFADAPT003"))
}
