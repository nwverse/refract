import SwiftUI

struct NativeHelpLink: RefractNativeView {
    let destination: RefractLinkDestination
    let policy: RefractLinkPolicy
    let handoff: RefractLinkHandoff
    @State private var isConfirming: Bool = false

    var body: some View {
        Button("Open help") { isConfirming = true }
            .confirmationDialog("Open \(destination.scheme)://\(destination.host)?", isPresented: $isConfirming) {
                Button("Open") {
                    guard policy.permits(destination) else { return }
                    handoff.begin(destination) { _ in isConfirming = false }
                }
                Button("Cancel", role: .cancel) {
                    isConfirming = false
                }
            }
    }
}

struct HelpLinkScreen: View {
    let handoff: RefractLinkHandoff

    var body: some View {
        VStack {
            NativeHelpLink(
                destination: RefractLinkDestination.https(host: "docs.example.test", path: "/help/start"),
                policy: RefractLinkPolicy(allowed: [
                    (scheme: "https", host: "docs.example.test"),
                    (scheme: "app+test", host: "router.example.test")
                ]),
                handoff: handoff
            )
            NativeHelpLink(
                destination: RefractLinkDestination.deepLink(scheme: "app+test", host: "router.example.test", path: "/article/42"),
                policy: RefractLinkPolicy(allowed: [
                    (scheme: "https", host: "docs.example.test"),
                    (scheme: "app+test", host: "router.example.test")
                ]),
                handoff: handoff
            )
        }
    }
}
