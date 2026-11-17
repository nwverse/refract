import Foundation
import RefractArkUI
import RefractCompose
import RefractFrontend
import RefractIR
import RefractMapping
import Testing

private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Test func typedTabsUseNativeSelectionCallbacksAndDestinations() throws {
    let fixture = repository.appendingPathComponent("Fixtures/navigation-tabs-menu")
    let input = try String(contentsOf: fixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    let mapping = try Mapping.load(data: Data(try String(contentsOf: fixture.appendingPathComponent("refract.json"), encoding: .utf8).utf8),
                                  file: "refract.json", resourceBaseURL: fixture)
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: input), mapping: mapping)
    #expect(unit.diagnostics.isEmpty)
    #expect(unit.module.screens.count == 3)
    guard case let .tabView(tabs, _)? = unit.module.screens.last?.body else {
        Issue.record("Expected the source TabView")
        return
    }
    #expect(tabs.selectionName == "tab")
    #expect(tabs.enumName == "HomeTab")
    #expect(tabs.destinations.map(\.caseName) == ["overview", "activity"])
    #expect(tabs.destinations.map(\.viewName) == ["OverviewScreen", "ActivityScreen"])
    #expect(tabs.menuActions.count == 2)

    let kotlin = try ComposeBackend().generate(module: unit.module, mapping: mapping)
    #expect(kotlin.contains("tab: HomeTab"))
    #expect(kotlin.contains("onTabChange: (HomeTab) -> Unit"))
    #expect(kotlin.contains("public fun HomeTabsScreenDestinations("))
    #expect(kotlin.contains("NavigationBarItem("))
    #expect(kotlin.contains("selected = tab == HomeTab.overview"))
    #expect(kotlin.contains("DropdownMenuItem("))
    #expect(kotlin.contains("model.refresh()"))
    #expect(kotlin.contains("val menuContentDescription = stringResource(R.string.menu_more)"))
    #expect(kotlin.contains("contentDescription = menuContentDescription"))
    #expect(!kotlin.contains("NavController"))
    #expect(!kotlin.contains("ModalDrawer"))
    #expect(!kotlin.contains("NavHost("))

    let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
    #expect(ark.contains("@Require @Param tab: HomeTab;"))
    #expect(ark.contains("@Event onTabChange: (value: HomeTab) => void"))
    #expect(ark.contains("Tabs({ barPosition: BarPosition.End, index: this.homeTabsScreenTabIndex })"))
    #expect(ark.contains("TabContent()"))
    #expect(ark.contains(".bindMenu(["))
    #expect(ark.contains("this.model.refresh();"))
    #expect(!ark.contains("NavPathStack"))
    #expect(!ark.contains("@Entry"))
    #expect(!ark.contains("SideBarContainer"))
}

@Test func tabSelectionRejectsScalarState() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum HomeTab: Hashable { case overview }
    struct OverviewScreen: View { var body: some View { Text(verbatim: "Overview") } }
    struct HomeTabsScreen: View {
        @State private var selected: Int = 0
        var body: some View {
            TabView(selection: $selected) {
                OverviewScreen().tabItem { Label("tab.overview", systemImage: "gear") }.tag(.overview)
            }
        }
    }
    """))
    #expect(unit.diagnostics.contains(where: { $0.code == "RFNAV402" }))
}

@Test func tabDestinationsMustCoverEveryCaseInOrder() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum HomeTab: Hashable { case overview; case activity }
    struct OverviewScreen: View { var body: some View { Text(verbatim: "Overview") } }
    struct HomeTabsScreen: View {
        @State private var tab: HomeTab = .overview
        var body: some View {
            TabView(selection: $tab) {
                OverviewScreen().tabItem { Label("tab.overview", systemImage: "gear") }.tag(.overview)
            }
        }
    }
    """))
    #expect(unit.diagnostics.contains(where: { $0.code == "RFNAV403" }))
}

@Test func tabMenuRejectsNonModelActions() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum HomeTab: Hashable { case overview }
    struct OverviewScreen: View { var body: some View { Text(verbatim: "Overview") } }
    struct HomeTabsScreen: View {
        @State private var tab: HomeTab = .overview
        var body: some View {
            TabView(selection: $tab) {
                OverviewScreen().tabItem { Label("tab.overview", systemImage: "gear") }.tag(.overview)
                    .toolbar {
                        ToolbarItem {
                            Menu {
                                Button("menu.refresh") { tab = .overview }
                            } label: { Label("menu.more", systemImage: "checkmark") }
                        }
                    }
            }
        }
    }
    """))
    #expect(unit.diagnostics.contains(where: { $0.code == "RFNAV404" }))
}

@Test func tabDestinationRejectsStoredInputs() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum HomeTab: Hashable { case overview }
    protocol OverviewModel: RefractModel { var title: String { get } }
    struct OverviewScreen: View {
        let model: OverviewModel
        var body: some View { Text(model.title) }
    }
    struct HomeTabsScreen: View {
        let model: OverviewModel
        @State private var tab: HomeTab = .overview
        var body: some View {
            TabView(selection: $tab) {
                OverviewScreen(model: model).tabItem { Label("tab.overview", systemImage: "gear") }.tag(.overview)
            }
        }
    }
    """))
    #expect(unit.diagnostics.contains(where: { $0.code == "RFNAV403" }))
}

@Test func tabSelectionRejectsNonHashableEnum() {
    let unit = Frontend.parse(SourceFile(path: "Input.swift", contents: """
    enum HomeTab { case overview }
    struct OverviewScreen: View { var body: some View { Text(verbatim: "Overview") } }
    struct HomeTabsScreen: View {
        @State private var tab: HomeTab = .overview
        var body: some View {
            TabView(selection: $tab) {
                OverviewScreen().tabItem { Label("tab.overview", systemImage: "gear") }.tag(.overview)
            }
        }
    }
    """))
    #expect(unit.diagnostics.contains(where: { $0.code == "RFNAV402" }))
}
