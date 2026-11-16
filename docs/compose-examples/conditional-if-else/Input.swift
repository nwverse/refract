import SwiftUI

struct ConditionalView: View {
    var isLoading: Bool

    var body: some View {
        VStack {
            if isLoading {
                Text("Loading…")
            } else {
                Text("Ready")
            }
        }
    }
}
