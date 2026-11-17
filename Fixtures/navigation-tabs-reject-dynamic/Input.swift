import SwiftUI

enum HomeTab: Hashable {
    case overview
}

struct OverviewScreen: View {
    var body: some View {
        Text(verbatim: "Overview")
    }
}

struct HomeTabsScreen: View {
    @State private var tab: HomeTab = .overview
    @State private var selected: Int = 0

    var body: some View {
        TabView(selection: $selected) {
            OverviewScreen()
                .tabItem { Label("tab.overview", systemImage: "gear") }
                .tag(.overview)
        }
    }
}
