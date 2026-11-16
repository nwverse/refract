import SwiftUI

struct SpacedRowView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Left")
            Text("Right")
        }
    }
}
