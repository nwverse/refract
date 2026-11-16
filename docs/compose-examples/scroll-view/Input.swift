import SwiftUI

struct ScrollableView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("First")
                Text("Second")
                Text("Third")
            }
        }
    }
}
