import SwiftUI

protocol SignupModel: RefractModel {
    var submitting: Bool { get }
    func save(email: String)
}

struct SignupScreen: View {
    let model: SignupModel
    @State private var form = refractForm {
        Field("email", initial: "", rules: .nonEmpty)
    }

    var body: some View {
        Form {
            Button("settings.submit") {
                form.submit(model.save)
            }
        } (form: $form)
    }
}
