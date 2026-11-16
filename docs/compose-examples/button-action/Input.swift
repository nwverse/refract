import SwiftUI

struct GreetingButtonView: View {
    var onGreet: () -> Void

    var body: some View {
        VStack {
            Button("Greet") {
                onGreet()
            }
        }
    }
}
