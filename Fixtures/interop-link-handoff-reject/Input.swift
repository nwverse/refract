import SwiftUI

struct NativeHelpLink: RefractNativeView {
    let destination: RefractLinkDestination
    let policy: RefractLinkPolicy
    let handoff: RefractLinkHandoff
    @State private var isConfirming: Bool = false

    var body: some View {
        Button("Open help") { isConfirming = true }
    }
}

struct HelpLinkScreen: View {
    let handoff: RefractLinkHandoff

    var body: some View {
        NativeHelpLink(
            destination: RefractLinkDestination.https(host: "other.example.test", path: "/help"),
            policy: RefractLinkPolicy(allowed: [(scheme: "https", host: "docs.example.test")]),
            handoff: handoff
        )
    }
}
