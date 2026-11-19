import SwiftUI

protocol ConversationModel: RefractModel {
    func openLink(_ url: String)
}

struct RuntimeMarkdown: View {
    let model: ConversationModel
    var body: some View {
        refractMarkdown(version: 1, blocks: model.markdown, onLink: .linkAction(model.openLink))
    }
}
