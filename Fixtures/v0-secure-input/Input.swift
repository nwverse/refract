import SwiftUI

struct SecureInputState: View {
    @State private var password: String = ""
    @State private var isRevealed: Bool = false

    var body: some View {
        VStack {
            SecureField("settings.password", text: $password)
            SecureField("settings.token", text: $password)
                .secureReveal($isRevealed)
        }
    }
}
