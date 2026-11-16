import SwiftUI

struct SpacedColumnView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("First")
            Text("Second")
        }
    }
}
