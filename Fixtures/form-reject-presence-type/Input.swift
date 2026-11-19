import SwiftUI

protocol SignupModel: RefractModel {
    var submissionError: String { get }
}

struct SignupScreen: View {
    let model: SignupModel

    var body: some View {
        VStack {
            if refractPresent(model.submissionError) {
                Text(model.submissionError)
            }
        }
    }
}
