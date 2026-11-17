import SwiftUI

struct NativeSelectionEmphasis: RefractNativeView {
    let emphasized: Bool
    let identity: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(verbatim: "Selection")
            .id(identity)
            .opacity(emphasized ? 1 : 0.5)
            .animation(reduceMotion ? nil : .easeInOut, value: emphasized)
    }
}

protocol SelectionEmphasisModel: RefractModel {
    var identity: String { get }
}

struct SelectionEmphasisScreen: View {
    let model: SelectionEmphasisModel
    @Binding var emphasized: Bool

    var body: some View {
        NativeSelectionEmphasis(emphasized: emphasized, identity: model.identity)
    }
}
