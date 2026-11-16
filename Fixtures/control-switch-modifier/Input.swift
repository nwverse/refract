import SwiftUI

enum PayloadContent {
    case text(String)
    case count(Int)
}

struct PayloadModifier: View {
    let content: PayloadContent
    var body: some View {
        switch content {
        case .text(let subject):
            Text(subject).frame(width: 44)
        case .count(let count):
            Text("content.count\(count)")
        }
    }
}
