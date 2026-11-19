import SwiftUI

enum WidthSizeClass {
    case compact
    case medium
}

struct AdaptiveScreen: View {
    let widthSizeClass: WidthSizeClass

    var body: some View {
        switch widthSizeClass {
        case .compact:
            Text(verbatim: "Compact")
        case .medium:
            Text(verbatim: "Medium")
        }
    }
}
