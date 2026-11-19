import SwiftUI

/// This wrapper changes no view content. It supplies the same explicit List
/// style to both variants; the compared generated body is the canonical Swift
/// source referenced directly by the Xcode target.
@MainActor
struct GeneratedSettingsScreen: View {
    @ObservedObject var model: BenchmarkSettingsModel

    var body: some View {
        SettingsScreen(model: model)
            .listStyle(.plain)
            .modifier(BenchmarkScrollDriver())
    }
}
