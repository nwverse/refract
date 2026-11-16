import SwiftUI

struct OverlayView: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("Background")
            Text("Foreground")
        }
    }
}
