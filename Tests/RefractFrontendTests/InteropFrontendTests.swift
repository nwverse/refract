import Testing
import RefractIR
@testable import RefractFrontend

@Test func frontendBuildsTypedNativeDeclarationAndCall() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct RoutePreview: RefractNativeView {
        let zoom: Double
        let showsTraffic: Bool
        var body: some View { Text(verbatim: "iOS") }
    }
    struct RouteScreen: View {
        var body: some View { RoutePreview(zoom: 12.0, showsTraffic: true) }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    #expect(unit.module.nativeDeclarations.count == 1)
    #expect(unit.module.nativeDeclarations[0].parameters.map(\.label) == ["zoom", "showsTraffic"])
    #expect(unit.module.nativeDeclarations[0].parameters.map(\.type) == [.double, .bool])
    guard case let .native(component, _) = unit.module.screens[0].body else {
        Issue.record("Expected a native reference")
        return
    }
    #expect(component.arguments.map(\.type) == [.double, .bool])
}

@Test func frontendBuildsTypedNativeImageResources() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct RemoteImage: RefractNativeView {
        let url: String
        let placeholder: Image
        let failure: Image
        let contentDescription: LocalizedStringKey
        var body: some View { placeholder }
    }
    struct Profile: View {
        let url: String
        var body: some View {
            RemoteImage(url: url, placeholder: Image("profile_placeholder"), failure: Image("profile_unavailable"), contentDescription: "profile.photo")
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    #expect(unit.module.nativeDeclarations[0].parameters.map(\.type) == [.string, .image, .image, .stringKey])
    guard case let .native(component, _) = unit.module.screens[0].body else {
        Issue.record("Expected a native image reference")
        return
    }
    #expect(component.arguments.map(\.type) == [.string, .image, .image, .stringKey])
    #expect(component.arguments[1].expression.value == .imageResource("profile_placeholder"))
    guard case let .localizedText(text) = component.arguments[3].expression.value else {
        Issue.record("Expected localized accessibility text")
        return
    }
    #expect(text.key == "profile.photo")
}

@Test(arguments: [
    "@State private var saved: Bool = false",
    "@Binding var saved: Bool",
])
func frontendResolvesNativeArgumentFromDeclaredState(_ declaration: String) throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Confirmation: RefractNativeView {
        let visible: Bool
        let identity: String
        var body: some View { Text(verbatim: "Saved") }
    }
    struct Screen: View {
        \(declaration)
        var body: some View { Confirmation(visible: saved, identity: "profile-save") }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .native(component, _) = unit.module.screens[0].body else {
        Issue.record("Expected a native reference")
        return
    }
    #expect(component.arguments.map(\.type) == [.bool, .string])
    #expect(component.arguments[0].expression.value == (declaration.hasPrefix("@State")
        ? .valueProperty(.state("saved")) : .valueProperty(.binding("saved"))))
    #expect(component.arguments[1].expression.value == .stringLiteral("profile-save"))
}

@Test func frontendRejectsNativeArgumentWithMismatchedStateType() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Confirmation: RefractNativeView {
        let visible: Bool
        var body: some View { Text(verbatim: "Saved") }
    }
    struct Screen: View {
        @State private var identity: String = "save"
        var body: some View { Confirmation(visible: identity) }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE002"])
    #expect(unit.diagnostics[0].rendered.contains("expects `visible: bool` but receives string"))
}

@Test func reduceMotionIsAnIOSPreferenceNotANativeArgument() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Confirmation: RefractNativeView {
        let visible: Bool
        @Environment(\\.accessibilityReduceMotion) private var reduceMotion
        var body: some View { Text(verbatim: "Saved") }
    }
    struct Screen: View {
        @State private var saved: Bool = false
        var body: some View { Confirmation(visible: saved) }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    #expect(unit.module.nativeDeclarations[0].parameters.map(\.label) == ["visible"])
}

@Test func unrelatedNativePropertyWrapperIsRejected() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Confirmation: RefractNativeView {
        let visible: Bool
        @Environment(\\.colorScheme) private var colorScheme
        var body: some View { Text(verbatim: "Saved") }
    }
    struct Screen: View {
        var body: some View { Confirmation(visible: true) }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE001"])
}

@Test func frontendRejectsMismatchedNativeArgumentType() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct RoutePreview: RefractNativeView {
        let zoom: Double
        var body: some View { Text(verbatim: "iOS") }
    }
    struct RouteScreen: View {
        var body: some View { RoutePreview(zoom: true) }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE002"])
    #expect(unit.diagnostics[0].rendered.contains("expects `zoom: double` but receives bool"))
}

@Test func frontendRejectsUndeclaredNativeView() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Bad: View { var body: some View { Gauge("photo") } }
    """))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE001"])
}

@Test func frontendRejectsNativeReferenceWithUnresolvedType() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Badge: RefractNativeView {
        let count: Int
        var body: some View { Text(verbatim: "iOS") }
    }
    struct Bad: View {
        var body: some View { Badge(count: count) }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFSEM001"])
}

@Test func frontendSelectsNoPlatformBranchDuringParsing() throws {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct PlatformScreen: View {
        var body: some View {
            refractView(
                ios: { Text(verbatim: "iOS").padding(refractValue(ios: 4, android: 4, harmonyOS: 4)) },
                android: { Text(verbatim: "Android").padding(refractValue(ios: 4, android: 12, harmonyOS: 12)) },
                harmonyOS: { Text(verbatim: "HarmonyOS").padding(refractValue(ios: 4, android: 12, harmonyOS: 16)) }
            )
        }
    }
    """))
    #expect(unit.diagnostics.isEmpty)
    guard case let .platformView(alternatives, _) = unit.module.screens[0].body else {
        Issue.record("Expected platform view alternatives")
        return
    }
    guard case let .text(androidText, androidModifiers, _) = alternatives.android[0],
          case let .text(harmonyText, harmonyModifiers, _) = alternatives.harmonyOS[0],
          case let .platformValue(androidPadding)? = androidModifiers.first?.arguments.first?.value,
          case let .platformValue(harmonyPadding)? = harmonyModifiers.first?.arguments.first?.value else {
        Issue.record("Expected selected scalar alternatives to stay typed")
        return
    }
    #expect(androidText.value == .verbatimText("Android"))
    #expect(harmonyText.value == .verbatimText("HarmonyOS"))
    #expect(androidPadding.value(for: .android).value == .numberLiteral("12"))
    #expect(harmonyPadding.value(for: .harmonyOS).value == .numberLiteral("16"))
}

@Test func frontendRejectsIncompleteAndDifferentlyTypedPlatformValues() {
    let missing = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Bad: View {
        var body: some View { Text("x").padding(refractValue(ios: 4, android: 12)) }
    }
    """))
    #expect(missing.diagnostics.map(\.code) == ["RFNATIVE003"])
    let mismatched = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Bad: View {
        var body: some View { Text(verbatim: refractValue(ios: "iOS", android: true, harmonyOS: "HarmonyOS")) }
    }
    """))
    #expect(mismatched.diagnostics.map(\.code) == ["RFNATIVE003"])
    #expect(mismatched.diagnostics[0].location?.line == 2)
}

@Test func frontendRejectsFreeFormConditionalCompilation() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Bad: View {
        var body: some View {
            #if os(iOS)
            Text(verbatim: "iOS")
            #else
            Text("Other")
            #endif
        }
    }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFVIEW005"])
    #expect(unit.diagnostics[0].location?.column == 9)
}

@Test func frontendRejectsDuplicateAndUnsupportedNativeDeclarations() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    struct Badge: RefractNativeView {
        var count: Int = 0
        var body: some View { Text(verbatim: "iOS") }
    }
    struct Screen: View { var body: some View { Badge(count: 1) } }
    """))
    #expect(unit.diagnostics.map(\.code) == ["RFNATIVE001"])
}
