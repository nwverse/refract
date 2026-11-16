import SwiftUI

enum Tab: String {
    case home
    case settings
    case profile
}

struct TabContentView: View {
    var tab: Tab

    var body: some View {
        VStack {
            switch tab {
            case .home:
                Text("Home")
            case .settings:
                Text("Settings")
            case .profile:
                Text("Profile")
            }
        }
    }
}
