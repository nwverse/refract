import SwiftUI

protocol ConversationModel: RefractModel {
    func openLink(_ url: String)
}

struct ConversationSnippet: View {
    let model: ConversationModel

    var body: some View {
        ScrollView {
            refractMarkdown(
                version: 1,
                blocks: [
                    .paragraph(id: "answer.summary", content: [
                        .localized("conversation.answer"),
                        .strong(.localized("conversation.important")),
                        .emphasis(.localized("conversation.note")),
                        .inlineCode(verbatim: "let answer = 42"),
                        .link(label: .localized("conversation.docs"), destination: .https(host: "example.com", path: "/docs")),
                    ]),
                    .codeBlock(
                        id: "answer.example",
                        language: .swift,
                        accessibilityLabel: .localized("conversation.code.label"),
                        code: "func answer() -> Int {\n    return 42\n}\n"
                    ),
                ],
                onLink: .linkAction(model.openLink)
            )
        }
    }
}

