import SwiftUI

struct SettingItem: Identifiable {
    let id: String
    let title: String
}

protocol SettingsListModel: RefractModel {
    var items: [SettingItem] { get }
}

struct ForEachList: View {
    let model: SettingsListModel
    let title: String?

    var body: some View {
        if let value = title {
            List {
                ForEach(model.items) { item in
                    VStack {
                        Text(value)
                        Text(item.title)
                    }
                }
            }
        } else {
            Text(verbatim: "Empty")
        }
    }
}
