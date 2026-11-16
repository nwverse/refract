import SwiftUI

struct MappingCard: View {
    var body: some View {
        CardRow(title: "settings.title") {
            Badge(title: "settings.enabled")
        }
        .padding(DesignSpacing.medium)
        .background(DesignColors.surface)
    }
}
