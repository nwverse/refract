import SwiftUI

struct TabContent: View {
    let tab: Tab

    var body: some View {
        switch tab {
        case .home:
            Text(verbatim: "Home")
        case .settings:
            Text(verbatim: "Settings")
        }
    }
}
