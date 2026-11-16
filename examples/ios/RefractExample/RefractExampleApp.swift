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
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Hand-written profile")
                    .font(.title)
                NavigationLink("Open shared layout") {
                    Hello()
                }
                NavigationLink("Keep native profile") {
                    NativeProfile()
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
