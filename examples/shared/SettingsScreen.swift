import SwiftUI

struct SettingsScreen: View {
    let model: SettingsModel
    @Binding var notificationsEnabled: Bool
    @State private var displayName: String = ""

    var body: some View {
        List {
            Section("settings.profile") {
                Text(model.title)
                TextField("settings.display.name", text: $displayName)
            }
            Section("settings.preferences") {
                Toggle("settings.notifications", isOn: $notificationsEnabled)
            }
            Section {
                Button("settings.save") {
                    model.save()
                }
            }
        }
    }
}
