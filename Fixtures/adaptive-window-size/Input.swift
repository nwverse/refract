import SwiftUI

enum WidthSizeClass {
    case compact
    case expanded
}

enum AdaptiveRoute: Hashable {
    case detail
}

protocol AdaptiveSettingsModel: RefractModel {
    var title: String { get }
    func save()
}

struct AdaptiveDetailScreen: View {
    let model: AdaptiveSettingsModel

    var body: some View {
        Text(model.title)
    }
}

struct AdaptiveNavigationScreen: View {
    let model: AdaptiveSettingsModel
    @State private var path: [AdaptiveRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                Text(model.title)
                NavigationLink("adaptive.open", value: .detail)
            }
            .navigationDestination(for: AdaptiveRoute.self) { route in
                switch route {
                case .detail:
                    AdaptiveDetailScreen(model: model)
                }
            }
        }
    }
}

struct AdaptiveSettingsScreen: View {
    let model: AdaptiveSettingsModel
    let widthSizeClass: WidthSizeClass
    @Binding var notificationsEnabled: Bool
    @Binding var displayName: String

    var body: some View {
        switch widthSizeClass {
        case .compact:
            VStack(alignment: .leading, spacing: .medium) {
                Text(model.title)
                TextField("settings.display.name", text: $displayName)
                Toggle("settings.notifications", isOn: $notificationsEnabled)
                Button("settings.save") { model.save() }
            }
            .padding(8)
        case .expanded:
            HStack(alignment: .top, spacing: .medium) {
                VStack(alignment: .leading, spacing: .medium) {
                    Text(model.title)
                    TextField("settings.display.name", text: $displayName)
                }
                .layoutPriority(1)
                VStack(alignment: .leading, spacing: .medium) {
                    Toggle("settings.notifications", isOn: $notificationsEnabled)
                    Button("settings.save") { model.save() }
                }
                .layoutPriority(1)
            }
            .padding(8)
        }
    }
}
