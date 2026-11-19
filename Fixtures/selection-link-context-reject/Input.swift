import SwiftUI

protocol SelectionMessageModel: RefractModel {
    func openLink(_ destination: String)
    func useAsContext(start: Int, end: Int, text: String)
    func editWithAI(start: Int, end: Int, text: String)
}

struct NativeSelectionMessage: RefractNativeView {
    let content: RefractSelectionContent
    let onLink: (String) -> Void
    let onUseAsContext: (RefractSelectionContext) -> Void
    let onEditWithAI: (RefractSelectionContext) -> Void
    var body: some View { Text(verbatim: content.text) }
}

struct SelectionMessageScreen: View {
    let model: SelectionMessageModel
    var body: some View {
        NativeSelectionMessage(
            content: RefractSelectionContent(text: "🌸", links: [
                RefractSelectionLink(range: RefractSelectionRange(start: 1, end: 2),
                                     destination: "https://example.test"),
            ]),
            onLink: { destination in model.openLink(destination) },
            onUseAsContext: { context in
                model.useAsContext(start: context.range.start, end: context.range.end, text: context.text)
            },
            onEditWithAI: { context in
                model.editWithAI(start: context.range.start, end: context.range.end, text: context.text)
            }
        )
    }
}
