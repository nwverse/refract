import SwiftUI

struct StaticList: View {
    var body: some View {
        List {
            Section("settings.general") {
                Text("settings.profile")
                Text("settings.notifications")
            }
            Section {
                Text("settings.about")
            }
        }
    }
}
