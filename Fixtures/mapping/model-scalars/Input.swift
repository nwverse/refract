import SwiftUI

protocol SettingsModel: RefractModel {
    var versionName: String { get }
}

struct VersionRow: View {
    let model: SettingsModel

    var body: some View {
        ReadOnlyRow(value: model.versionName)
    }
}
