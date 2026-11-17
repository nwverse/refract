import SwiftUI

enum HomeTab: Hashable {
    case overview
}

protocol OverviewModel: RefractModel {
    var title: String { get }
}

struct OverviewScreen: View {
    let model: OverviewModel

    var body: some View {
        Text(model.title)
    }
}

struct HomeTabsScreen: View {
    let model: OverviewModel
    @State private var tab: HomeTab = .overview

    var body: some View {
        TabView(selection: $tab) {
            OverviewScreen(model: model)
                .tabItem { Label("tab.overview", systemImage: "gear") }
                .tag(.overview)
        }
    }
}
