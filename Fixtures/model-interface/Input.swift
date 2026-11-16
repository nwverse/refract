import SwiftUI

protocol ExtensionSettingsModel: RefractModel {
    var title: String { get }
    var isEnabled: Bool { get }
    func setEnabled(_ value: Bool)
}

struct ExtensionSettings: View {
    let model: ExtensionSettingsModel

    var body: some View {
        VStack {
            Text(model.title)
            Button(verbatim: "Disable") { model.setEnabled(false) }
        }
    }
}
