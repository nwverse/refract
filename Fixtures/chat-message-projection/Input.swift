import SwiftUI

struct ChatBlock: Identifiable {
    let id: String
    let text: String
}

struct ChatMessage: Identifiable {
    let id: String
    let revision: UInt64
    let blocks: [ChatBlock]
    let finalized: Bool
}

protocol ConversationModel: RefractModel {
    var messages: [ChatMessage] { get }
}

struct MessageBlock: View {
    let message: ChatMessage
    let block: ChatBlock

    var body: some View {
        VStack {
            Text(block.text)
            if message.finalized {
                Text(verbatim: "Final")
            }
        }
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        VStack {
            Text(message.id)
            ForEach(message.blocks) { block in
                MessageBlock(message: message, block: block)
            }
            Text(verbatim: "Row footer")
        }
    }
}

struct ConversationScreen: View {
    let model: ConversationModel

    var body: some View {
        List(model.messages) { message in
            MessageRow(message: message)
        }
    }
}
