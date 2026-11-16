import SwiftUI

struct StyledText: View {
    var body: some View {
        Text(verbatim: "Appearance")
            .font(DesignTypography.title)
            .foregroundStyle(DesignColors.secondary)
            .padding(DesignSpacing.medium)
            .frame(maxWidth: .infinity)
            .background(DesignColors.surface)
            .cornerRadius(DesignRadius.small)
    }
}
