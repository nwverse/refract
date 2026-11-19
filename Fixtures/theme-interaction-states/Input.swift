import SwiftUI

struct ThemedSettingsControl: View {
    @Binding var isEnabled: Bool
    @Binding var isPressed: Bool
    @Binding var isFocused: Bool

    var body: some View {
        Text(verbatim: "Appearance and notifications")
            .font(DesignTypography.body)
            .foregroundStyle(DesignColors.content)
            .padding(DesignSpacing.medium)
            .background(refractInteractionColor(
                DesignColors.action,
                enabled: isEnabled,
                pressed: isPressed,
                focused: isFocused
            ))
            .cornerRadius(DesignRadius.medium)
    }
}
