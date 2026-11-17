import SwiftUI

struct MissingInteractionState: View {
    @Binding var isEnabled: Bool
    @Binding var isPressed: Bool
    @Binding var isFocused: Bool

    var body: some View {
        Text(verbatim: "Notifications")
            .background(refractInteractionColor(
                DesignColors.action,
                enabled: isEnabled,
                pressed: isPressed,
                focused: isFocused
            ))
    }
}
