import SwiftUI

enum WidthSizeClass {
    case compact
    case expanded
}

struct AdaptiveScreen: View {
    let deviceClass: WidthSizeClass

    var body: some View {
        Text(verbatim: "Wrong ownership")
    }
}
