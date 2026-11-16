import SwiftUI

protocol AsyncSettingsModel: RefractModel {
    func refresh() async
}

struct UnsupportedAsyncModel: View {
    let model: AsyncSettingsModel

    var body: some View {
        Text("Unsupported")
    }
}
