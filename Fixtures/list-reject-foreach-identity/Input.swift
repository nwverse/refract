import SwiftUI

struct SettingItem: Identifiable {
    let id: String
    let title: String
}

protocol SettingsListModel: RefractModel {
    var items: [SettingItem] { get }
}

struct RejectedForEachIdentity: View {
    let model: SettingsListModel

    var body: some View {
        List {
            ForEach(model.items, id: \.self) { item in
                Text(item.title)
            }
        }
    }
}
