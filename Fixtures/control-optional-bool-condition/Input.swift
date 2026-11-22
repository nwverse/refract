import SwiftUI

struct OptionalEnabled: View {
    let maybeEnabled: Bool?

    var body: some View {
        if let enabled = maybeEnabled {
            if enabled {
                Text("content.enabled")
            } else {
                Text("content.disabled")
            }
        } else {
            Text("content.unknown")
        }
    }
}
