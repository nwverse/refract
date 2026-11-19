import SwiftUI

protocol SignupModel: RefractModel {
    var submitting: Bool { get }
    @refractText var submissionError: String { get }
    @refractAsync func submit(email: String, password: String, confirmation: String)
    @refractAsync func retry(email: String, password: String, confirmation: String)
}

struct SignupScreen: View {
    let model: SignupModel
    @State private var form = refractForm {
        Field("email", initial: "", rules: .nonEmpty)
        Field("password", initial: "", rules: [.nonEmpty, .equals("confirmation")])
        Field("confirmation", initial: "")
    }

    var body: some View {
        Form {
            TextField("settings.email", text: $form.email)
            TextField("settings.password", text: $form.password)
            TextField("settings.confirmation", text: $form.confirmation)
            if model.submitting {
                Text(verbatim: "Submitting…")
            }
            if refractPresent(model.submissionError) {
                Text(model.submissionError)
            }
            Button("settings.submit") {
                form.submit(model.submit)
            }
            .disabled(model.submitting)
            if refractPresent(model.submissionError) {
                Button("settings.retry") {
                    form.submit(model.retry)
                }
                .disabled(model.submitting)
            }
        } (form: $form)
    }
}
