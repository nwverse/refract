import SwiftUI

enum Tab {
    case home
    case settings
}

struct MissingCase: View {
    let tab: Tab

    var body: some View {
        switch tab {
        case .home:
            Text(verbatim: "Home")
        default:
            Text(verbatim: "Other")
        }
    }
}
