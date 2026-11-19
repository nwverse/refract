import SwiftUI

struct NativeSaveConfirmation: RefractNativeView {
    let visible: Bool
    let identity: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if visible {
            Text("Saved")
                .id(identity)
                .transition(reduceMotion ? .identity : .opacity)
        }
    }
}

struct SaveConfirmationScreen: View {
    @Binding var saved: Bool

    var body: some View {
        NativeSaveConfirmation(visible: saved, identity: "profile-save")
    }
}
