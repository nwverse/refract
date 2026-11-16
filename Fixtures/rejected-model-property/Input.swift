import SwiftUI

protocol WritableSettingsModel: RefractModel {
    var title: String { get set }
}

struct UnsupportedWritableModel: View {
    let model: WritableSettingsModel

    var body: some View {
        Text(verbatim: "Unsupported")
    }
}
