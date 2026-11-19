import SwiftUI

protocol SyntheticNotificationHost: RefractNotificationHost {
    func present(_ id: String, revision: Int)
    func cancel(_ id: String, revision: Int)
    func confirm(_ id: String, revision: Int)
}

struct NotificationScreen: View {
    let notifications: SyntheticNotificationHost
    @RefractNativeValue var notification: RefractNotificationEvent
    @RefractNativeValue var correlation: RefractNotificationEvent

    var body: some View {
        VStack {
            Text("synthetic.notification.id\(correlation.id)")
            switch notification {
            case .unavailable:
                Text(verbatim: "Capability unavailable; permission remains app-owned")
            case .accepted:
                Text(verbatim: "Accepted by the app; not scheduled or delivered")
            case .scheduled:
                Text(verbatim: "App confirms scheduling")
            case .delivered:
                Text(verbatim: "App confirms synthetic delivery")
            case .cancelled:
                Text(verbatim: "App confirms cancellation")
            case .stale:
                Text(verbatim: "Stale revision; no delivery claim")
            case .confirmationRequired:
                Text(verbatim: "Explicit native confirmation required")
                Button("synthetic.notification.confirm") {
                    notifications.confirm(correlation.id, revision: correlation.revision)
                }
            case .confirmed:
                Text(verbatim: "App confirms the synthetic request")
            }
            Button("synthetic.notification.present") {
                notifications.present(correlation.id, revision: correlation.revision)
            }
            Button("synthetic.notification.cancel") {
                notifications.cancel(correlation.id, revision: correlation.revision)
            }
        }
        .refractNativeValue(notification.state)
        .refractNativeValue(correlation.id)
    }
}
