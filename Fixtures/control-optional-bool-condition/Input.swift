import SwiftUI

struct OptionalEnabled: View {
    let maybeEnabled: Bool?
    let maybeReady: Bool?

    var body: some View {
        if let enabled = maybeEnabled {
            if let ready = maybeReady {
                VStack {
                    if enabled {
                        Text("content.enabled")
                    } else if ready {
                        Text("content.disabled")
                    } else {
                        Text("content.unavailable")
                    }
                }
            } else {
                Text("content.pending")
            }
        } else {
            Text("content.unknown")
        }
    }
}
