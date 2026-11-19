import SwiftUI

protocol SyncAccessibilityModel: RefractModel {
    var syncStatus: String { get }
    func syncNow()
    func showDetails()
}

struct AccessibilityActionsTraversal: View {
    let model: SyncAccessibilityModel

    var body: some View {
        refractView(
            ios: {
                VStack(alignment: .leading, spacing: .medium) {
                    Text("accessibility.sync.title")
                        .accessibilityValue(Text("accessibility.sync.status\(model.syncStatus)"))
                        .accessibilitySortPriority(0)
                    Button("accessibility.sync.now") {
                        model.syncNow()
                    }
                    .accessibilityLabel(Text("accessibility.sync.label"))
                    .accessibilityHint(Text("accessibility.sync.hint"))
                    .accessibilityValue(Text("accessibility.sync.status\(model.syncStatus)"))
                    .accessibilityAction(named: Text("accessibility.sync.action")) {
                        model.syncNow()
                    }
                    .accessibilitySortPriority(-1)
                    Button("accessibility.sync.details") {
                        model.showDetails()
                    }
                    .accessibilitySortPriority(-2)
                }
                .padding(16)
            },
            android: {
                VStack(alignment: .leading, spacing: .medium) {
                    Text("accessibility.sync.title")
                    .accessibilityValue(Text("accessibility.sync.status\(model.syncStatus)"))
                    Button("accessibility.sync.now") {
                        model.syncNow()
                    }
                    .accessibilityIdentifier("sync_now")
                    .accessibilityLabel(Text("accessibility.sync.label"))
                    .accessibilityHint(Text("accessibility.sync.hint"))
                    .accessibilityValue(Text("accessibility.sync.status\(model.syncStatus)"))
                    .accessibilityAction(named: Text("accessibility.sync.action")) {
                        model.syncNow()
                    }
                    Button("accessibility.sync.details") {
                        model.showDetails()
                    }
                    .accessibilityIdentifier("sync_details")
                }
                .accessibilityTraversal([
                    .accessibility("sync_now"),
                    .accessibility("sync_details", after: "sync_now"),
                ])
                .padding(16)
            },
            harmonyOS: {
                VStack(alignment: .leading, spacing: .medium) {
                    Text("accessibility.sync.title")
                    .accessibilityValue(Text("accessibility.sync.status\(model.syncStatus)"))
                    Button("accessibility.sync.now") {
                        model.syncNow()
                    }
                    .accessibilityIdentifier("sync_now")
                    .accessibilityLabel(Text("accessibility.sync.label"))
                    .accessibilityHint(Text("accessibility.sync.hint"))
                    .accessibilityValue(Text("accessibility.sync.status\(model.syncStatus)"))
                    .accessibilityAction(named: Text("accessibility.sync.action")) {
                        model.syncNow()
                    }
                    Button("accessibility.sync.details") {
                        model.showDetails()
                    }
                    .accessibilityIdentifier("sync_details")
                }
                .accessibilityTraversal([
                    .accessibility("sync_now"),
                    .accessibility("sync_details", after: "sync_now"),
                ])
                .padding(16)
            }
        )
    }
}
