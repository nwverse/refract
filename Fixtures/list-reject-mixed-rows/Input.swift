import SwiftUI

struct SettingItem: Identifiable {
    let id: String
    let title: String
}

protocol SettingsListModel: RefractModel {
    var items: [SettingItem] { get }
}

struct MixedRows: View {
    let model: SettingsListModel

    var body: some View {
        List {
            Text(verbatim: "Header")
            ForEach(model.items) { item in
                Text(item.title)
            }
        }
    }
}
