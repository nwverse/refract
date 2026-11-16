import SwiftUI

struct SettingItem: Identifiable {
    let id: String
    let title: String
}

protocol SettingsListModel: RefractModel {
    var items: [SettingItem] { get }
}

struct MisplacedForEach: View {
    let model: SettingsListModel

    var body: some View {
        VStack {
            ForEach(model.items) { item in
                Text(item.title)
            }
        }
    }
}
