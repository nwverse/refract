import SwiftUI

protocol ShareCapabilityModel: RefractModel {
    func cancelShare()
}

struct NativeShareCapability: RefractNativeView {
    let identifier: String
    let revision: Int
    let onCancel: () -> Void

    var body: some View {
        Button("media.share.cancel") { onCancel() }
    }
}

struct ShareCapabilityScreen: View {
    let identifier: String
    let revision: Int
    let model: ShareCapabilityModel

    var body: some View {
        NativeShareCapability(
            identifier: identifier,
            revision: revision,
            onCancel: { model.cancelShare() },
            recipient: "synthetic-recipient"
        )
    }
}
