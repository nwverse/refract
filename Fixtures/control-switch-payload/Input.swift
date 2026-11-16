import SwiftUI

enum Content {
    case text(String)
    case count(Int)
}

struct ContentView: View {
    let content: Content

    var body: some View {
        switch content {
        case .text(let text):
            Text(text)
        case .count(let count):
            Text("content.count\(count)")
        }
    }
}
