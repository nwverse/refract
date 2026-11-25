import SwiftUI

struct InvalidProgress: View {
    @State private var progress: Double = "invalid"

    var body: some View {
        Text(verbatim: "Invalid")
    }
}
