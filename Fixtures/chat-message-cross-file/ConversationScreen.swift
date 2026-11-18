import SwiftUI
struct ConversationScreen: View {
    let model: ConversationModel

    var body: some View {
        List(model.messages) { message in
            MessageRow(message: message)
        }
    }
}
