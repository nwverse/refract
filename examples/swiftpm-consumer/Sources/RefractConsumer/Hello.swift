import SwiftUI

struct Hello: View {
    var body: some View {
        VStack {
            Text("hello.title")
            Button("hello.go") { }
        }
    }
}

public func consumerHostName() -> String { "RefractConsumer" }
