import SwiftUI

protocol ConversationModel: RefractModel {
    func openLink(_ url: String)
}

struct UnsafeMarkdown: View {
    let model: ConversationModel
    var body: some View {
        refractMarkdown(version: 1, blocks: [
            .paragraph(id: "answer.link", content: [
                .link(label: .localized("conversation.docs"), destination: .https(host: "user@example.com", path: "/docs")),
            ]),
        ], onLink: .linkAction(model.openLink))
    }
}
