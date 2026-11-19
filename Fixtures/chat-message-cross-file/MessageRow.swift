import SwiftUI
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
