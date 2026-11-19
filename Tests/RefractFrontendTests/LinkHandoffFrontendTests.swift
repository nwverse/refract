import Testing
import RefractIR
@testable import RefractFrontend

private func linkSource(destination: String, policy: String = #"RefractLinkPolicy(allowed: [(scheme: "https", host: "docs.example.test")])"#) -> String {
    """
    import SwiftUI
    struct NativeLink: RefractNativeView {
        let destination: RefractLinkDestination
        let policy: RefractLinkPolicy
        let handoff: RefractLinkHandoff
        @State private var isConfirming: Bool = false
        var body: some View { Button("Open") { isConfirming = true } }
    }
    struct HelpLinkScreen: View {
        let handoff: RefractLinkHandoff
        var body: some View {
            NativeLink(destination: \(destination), policy: \(policy), handoff: handoff)
        }
    }
    """
}

@Test func typedExternalAndDeepLinkValuesStayInTheSharedIR() {
    for (destination, expectedKind, expectedScheme) in [
        (#"RefractLinkDestination.https(host: "docs.example.test", path: "/help/start")"#, LinkDestination.Kind.external, "https"),
        (#"RefractLinkDestination.deepLink(scheme: "app+test", host: "router.example.test", path: "/article/42")"#, LinkDestination.Kind.deepLink, "app+test"),
    ] {
        let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: linkSource(destination: destination,
            policy: #"RefractLinkPolicy(allowed: [(scheme: "https", host: "docs.example.test"), (scheme: "app+test", host: "router.example.test")])"#)))
        #expect(unit.diagnostics == [])
        guard case let .native(component, _) = unit.module.screens.first?.body,
              case let .linkDestination(value) = component.arguments.first?.expression?.value,
              case let .linkPolicy(policy) = component.arguments[1].expression?.value else {
            Issue.record("Expected typed link arguments")
            return
        }
        #expect(value.kind == expectedKind)
        #expect(value.scheme == expectedScheme)
        #expect(policy.permits(value))
        #expect(component.arguments[2].type == .linkHandoff)
        #expect(unit.module.screens.first?.parameters.first?.itemType == "RefractLinkHandoff")
    }
}

@Test(arguments: [
    (#""https://docs.example.test/help""#, "RFLINK001"),
    (#"RefractLinkDestination.deepLink(scheme: "javascript", host: "docs.example.test", path: "/help")"#, "RFLINK002"),
    (#"RefractLinkDestination.deepLink(scheme: "intent", host: "docs.example.test", path: "/help")"#, "RFLINK002"),
    (#"RefractLinkDestination.deepLink(scheme: "https", host: "docs.example.test", path: "/help")"#, "RFLINK002"),
    (#"RefractLinkDestination.https(host: "*.example.test", path: "/help")"#, "RFLINK002"),
    (#"RefractLinkDestination.https(host: "user@example.test", path: "/help")"#, "RFLINK002"),
    (#"RefractLinkDestination.https(host: "example.test:443", path: "/help")"#, "RFLINK002"),
    (#"RefractLinkDestination.https(host: "docs.example.test", path: "/help?next=/private")"#, "RFLINK002"),
    (#"RefractLinkDestination.https(host: "docs.example.test", path: "/help/../private")"#, "RFLINK002"),
    (#"RefractLinkDestination.https(host: "docs.example.test", path: "/help#top")"#, "RFLINK002"),
])
func malformedOrUnsafeLinkInputFailsAtBuildTime(destination: String, code: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: linkSource(destination: destination)))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.map(\.code) == [code])
}

@Test func aDestinationOutsideItsExactAllowlistIsRejected() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: linkSource(
        destination: #"RefractLinkDestination.https(host: "other.example.test", path: "/help")"#)))
    #expect(unit.diagnostics.map(\.code) == ["RFLINK002"])
    #expect(unit.diagnostics[0].rendered.contains("outside its exact scheme/host allowlist"))
}

@Test(arguments: [
    "RefractLinkPolicy(allowed: [])",
    #"RefractLinkPolicy(allowed: [(scheme: "*", host: "docs.example.test")])"#,
    #"RefractLinkPolicy(allowed: [(scheme: "https", host: "docs.example.test"), (scheme: "https", host: "docs.example.test")])"#,
    #"RefractLinkPolicy(allowed: destinations)"#,
])
func dynamicWildcardAndDuplicatePoliciesAreRejected(policy: String) {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: linkSource(
        destination: #"RefractLinkDestination.https(host: "docs.example.test", path: "/help")"#, policy: policy)))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.map(\.code).allSatisfy { $0 == "RFLINK001" || $0 == "RFLINK002" })
}

@Test func privateConfirmationStateIsOnlyAllowedForLinkComponents() {
    let source = linkSource(destination: #"RefractLinkDestination.https(host: "docs.example.test", path: "/help")"#)
        .replacingOccurrences(of: "let policy: RefractLinkPolicy", with: "let policy: String")
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: source))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.contains { $0.code == "RFNATIVE001" })
}

@Test func linkHandoffCannotBeConstructedInsideTheView() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: linkSource(
        destination: #"RefractLinkDestination.https(host: "docs.example.test", path: "/help")"#)
        .replacingOccurrences(of: "handoff: handoff", with: "handoff: RefractLinkHandoff()")))
    #expect(unit.hasErrors)
    #expect(unit.diagnostics.contains { $0.code == "RFLINK001" })
}
