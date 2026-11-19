import SwiftUI

protocol SyntheticBackgroundHost: RefractBackgroundWorkHost {
    func schedule(_ id: String, revision: Int)
    func cancel(_ id: String, revision: Int)
    func confirm(_ id: String, revision: Int)
}

struct BackgroundWorkScreen: View {
    let work: SyntheticBackgroundHost
    @RefractNativeValue var workEvent: RefractBackgroundWorkEvent
    @RefractNativeValue var correlation: RefractBackgroundWorkEvent

    var body: some View {
        VStack {
            Text("synthetic.work.id\(correlation.id)")
            switch workEvent {
            case .unavailable:
                Text(verbatim: "Background capability unavailable")
            case .accepted:
                Text(verbatim: "Accepted by the app; no execution claim")
            case .scheduled:
                Text(verbatim: "App confirms scheduling; still not executed")
            case .completed:
                Text(verbatim: "App confirms synthetic completion")
            case .cancelled:
                Text(verbatim: "App confirms cancellation")
            case .stale:
                Text(verbatim: "Stale revision; no execution claim")
            case .confirmationRequired:
                Text(verbatim: "Explicit native confirmation required")
                Button("synthetic.work.confirm") {
                    work.confirm(correlation.id, revision: correlation.revision)
                }
            case .confirmed:
                Text(verbatim: "App confirms the synthetic work")
            }
            Button("synthetic.work.schedule") {
                work.schedule(correlation.id, revision: correlation.revision)
            }
            Button("synthetic.work.cancel") {
                work.cancel(correlation.id, revision: correlation.revision)
            }
        }
        .refractNativeValue(workEvent.state)
        .refractNativeValue(correlation.id)
    }
}
