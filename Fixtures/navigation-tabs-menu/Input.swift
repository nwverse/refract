import SwiftUI

enum HomeTab: Hashable {
    case overview
    case activity
}

protocol OverviewModel: RefractModel {
    var title: String { get }
    func refresh()
    func reset()
}

struct OverviewScreen: View {
    var body: some View {
        Text("tab.overview.body")
    }
}

struct ActivityScreen: View {
    var body: some View {
        Text("tab.activity.body")
    }
}

struct HomeTabsScreen: View {
    let model: OverviewModel
    @State private var tab: HomeTab = .overview

    var body: some View {
        TabView(selection: $tab) {
            OverviewScreen()
                .tabItem { Label("tab.overview", systemImage: "gear") }
                .tag(.overview)
            ActivityScreen()
                .tabItem { Label("tab.activity", systemImage: "person") }
                .tag(.activity)
                .toolbar {
                    ToolbarItem {
                        Menu {
                            Button("menu.refresh") { model.refresh() }
                            Button("menu.reset") { model.reset() }
                        } label: {
                            Label("menu.more", systemImage: "checkmark")
                        }
                    }
                }
        }
    }
}
