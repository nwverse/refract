import SwiftUI

/// Native measurement owner. The source's model, state and NavigationStack stay
/// in the content supplied by the application; this host only supplies width class.
struct AdaptiveHost<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let content: (WidthSizeClass) -> Content

    init(@ViewBuilder content: @escaping (WidthSizeClass) -> Content) {
        self.content = content
    }

    var body: some View {
        content(horizontalSizeClass == .compact ? .compact : .expanded)
    }
}
