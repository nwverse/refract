import SwiftUI

protocol ConversationModel: RefractModel {
    func openLink(_ url: String)
}

struct HTMLMarkdown: View {
    let model: ConversationModel
    var body: some View {
        refractMarkdown(version: 1, blocks: [
            .html(id: "answer.html", source: "<b>not a typed node</b>"),
        ], onLink: .linkAction(model.openLink))
    }
}
