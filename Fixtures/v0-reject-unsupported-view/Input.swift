import SwiftUI

struct UnsupportedView: View {
    var body: some View {
        GeometryReader { proxy in
            Text(verbatim: "Hello")
        }
    }
}
