import SwiftUI

@main
struct RefractExampleApp: App {
    var body: some Scene {
        WindowGroup {
            NativeNavigation()
        }
    }
}

private struct NativeNavigation: View {
    @StateObject private var model = AppSettingsModel()
    @State private var notificationsEnabled = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Hand-written profile")
                    .font(.title)
                NavigationLink("Open shared layout") {
                    Hello()
                }
                NavigationLink("Generated settings") {
                    SettingsScreen(model: model, notificationsEnabled: $notificationsEnabled)
                }
                NavigationLink("Hand-written settings (rollback)") {
                    HandWrittenSettingsScreen(model: model, notificationsEnabled: $notificationsEnabled)
                }
                NavigationLink("Native component in shared UI") {
                    NativeComponentScreen()
                }
            }
            .padding()
            .navigationTitle("Refract example")
        }
    }
}

private struct NativeProfile: View {
    var body: some View {
        Text("This profile remains hand-written during adoption and rollback.")
            .padding()
            .navigationTitle("Native profile")
    }
}
