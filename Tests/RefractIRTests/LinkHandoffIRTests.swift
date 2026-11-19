import Foundation
import Testing
@testable import RefractIR

@Test func linkValuesHaveStableCodableRoundTrips() throws {
    let destination = LinkDestination(kind: .deepLink, scheme: "app+test", host: "router.example.test", path: "/article/42")
    let policy = LinkPolicy(allowed: [
        LinkAllowlistEntry(scheme: "https", host: "docs.example.test"),
        LinkAllowlistEntry(scheme: "app+test", host: "router.example.test"),
    ])
    #expect(policy.permits(destination))
    #expect(!policy.permits(LinkDestination(kind: .external, scheme: "https", host: "other.example.test", path: "/help")))
    let component = NativeComponent(name: "NativeHelpLink", arguments: [
        NativeArgument(label: "destination", expression: Expression(.linkDestination(destination)), type: .linkDestination),
        NativeArgument(label: "policy", expression: Expression(.linkPolicy(policy)), type: .linkPolicy),
        NativeArgument(label: "handoff", expression: Expression(.reference("handoff")), type: .linkHandoff),
    ])
    let encoded = try JSONEncoder().encode(component)
    #expect(try JSONDecoder().decode(NativeComponent.self, from: encoded) == component)
}

@Test func sourceLinkPreludeDoesNotOpenURLs() throws {
    let example = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("examples/ios/RefractExample/RefractLinkSource.swift")
    let source = try String(contentsOf: example, encoding: .utf8)
    #expect(source == "import SwiftUI\n\n// App-owned source declarations; no Refract library or runtime is linked.\n"
        + LinkHandoffIR.sourcePrelude + "\n")
    #expect(LinkHandoffIR.sourcePrelude.contains("protocol RefractLinkHandoff"))
    #expect(!LinkHandoffIR.sourcePrelude.contains("openURL"))
    #expect(!LinkHandoffIR.sourcePrelude.contains("startActivity"))
}
