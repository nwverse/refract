import SwiftUI

struct InsecureReveal: View {
    @State private var password: String = ""

    var body: some View {
        SecureField("settings.password", text: $password)
            .secureReveal(.constant(true))
    }
}
