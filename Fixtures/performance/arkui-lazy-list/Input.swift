import SwiftUI

struct SettingItem: Identifiable {
    let id: Int
    let title: String
    let enabled: Bool
}

protocol SettingsListModel: RefractModel {
    var items: [SettingItem] { get }
}

struct SettingsList: View {
    let model: SettingsListModel

    var body: some View {
        List(model.items) { item in
            HStack {
                Text(item.title)
                Text(item.enabled ? "Enabled" : "Disabled")
            }
        }
    }
}
