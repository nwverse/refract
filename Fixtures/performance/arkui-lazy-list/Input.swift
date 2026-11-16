import SwiftUI

struct SettingItem: Identifiable {
    let id: Int
    let title: String
    let enabled: Bool
}

struct SettingsList: View {
    let items: [SettingItem]

    var body: some View {
        List(items) { item in
            HStack {
                Text(item.title)
                Text(item.enabled ? "Enabled" : "Disabled")
            }
        }
    }
}
