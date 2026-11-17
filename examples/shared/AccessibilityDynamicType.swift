import SwiftUI

protocol AccessibilityModel: RefractModel {
    var headline: String { get }
    var quietHoursDescription: String { get }
    func save()
}

struct AccessibilityDynamicType: View {
    let model: AccessibilityModel
    @Binding var notificationsEnabled: Bool
    @Binding var displayName: String

    var body: some View {
        VStack(alignment: .leading, spacing: .medium) {
            Text(model.headline)
            Text("settings.section").font(DesignTypography.sectionTitle)
            TextField("settings.display.name", text: $displayName)
            Toggle("settings.notifications", isOn: $notificationsEnabled)
            refractView(
                ios: {
                    Toggle("settings.quiet.hours", isOn: $notificationsEnabled)
                        .labelsHidden()
                        .accessibilityLabel(model.quietHoursDescription)
                },
                android: {
                    Toggle("settings.quiet.hours", isOn: $notificationsEnabled)
                        .labelsHidden()
                        .refractNativeModifier(.contentDescription(model.quietHoursDescription))
                },
                harmonyOS: {
                    Toggle("settings.quiet.hours", isOn: $notificationsEnabled)
                        .labelsHidden()
                        .accessibilityLabel(model.quietHoursDescription)
                }
            )
            Button("settings.save") {
                model.save()
            }
        }
        .padding(16)
    }
}
