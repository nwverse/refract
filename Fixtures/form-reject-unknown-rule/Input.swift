import SwiftUI

struct SignupScreen: View {
    @State private var form = refractForm {
        Field("email", initial: "", rules: [.nonEmpty, .minLength(3)])
    }

    var body: some View {
        Form {
            Text(verbatim: "Email")
        } (form: $form)
    }
}
