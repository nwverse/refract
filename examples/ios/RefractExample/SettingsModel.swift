import SwiftUI

final class AppSettingsModel: ObservableObject, SettingsModel {
    @Published var title: String

    init(title: String = "Profile settings") {
        self.title = title
    }

    func save() {
        // The native application owns persistence; no generated business logic.
    }
}

struct HandWrittenSettingsScreen: View {
    @ObservedObject var model: AppSettingsModel
    @Binding var notificationsEnabled: Bool
    @State private var displayName: String = ""

    var body: some View {
        Form {
            Section("Profile") {
                Text(model.title)
                TextField("Display name", text: $displayName)
            }
            Section("Preferences") {
                Toggle("Notifications", isOn: $notificationsEnabled)
            }
            Section {
                Button("Save", action: model.save)
            }
        }
        .navigationTitle("Native settings")
    }
}
