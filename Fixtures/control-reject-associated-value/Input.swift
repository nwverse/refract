import SwiftUI

enum Content {
    case loading
    case text(String)
}

struct UnsupportedPayload: View {
    let content: Content

    var body: some View {
        switch content {
        case .loading:
            Text(verbatim: "Loading")
        case .text(let value):
            Text(verbatim: value)
        }
    }
}
