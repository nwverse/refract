import SwiftUI

public struct RefractSelectionRange {
    public var start: Int
    public var end: Int
    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public struct RefractSelectionLink {
    public var range: RefractSelectionRange
    public var destination: String
    public init(range: RefractSelectionRange, destination: String) {
        self.range = range
        self.destination = destination
    }
}

public struct RefractSelectionContext {
    public var text: String
    public var range: RefractSelectionRange
    public init(text: String, range: RefractSelectionRange) {
        self.text = text
        self.range = range
    }
}

public struct RefractSelectionContent {
    public var text: String
    public var links: [RefractSelectionLink]
    public init(text: String, links: [RefractSelectionLink] = []) {
        self.text = text
        self.links = links
    }
}

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

    var body: some View {
        // The app supplies actual selection handles and gesture policy in this host.
        VStack {
            Text(verbatim: content.text).textSelection(.enabled)
            Button("selection.context") {
                onUseAsContext(RefractSelectionContext(text: content.text,
                    range: RefractSelectionRange(start: 0, end: 0)))
            }
            Button("selection.edit") {
                onEditWithAI(RefractSelectionContext(text: content.text,
                    range: RefractSelectionRange(start: 0, end: 0)))
            }
        }
    }
}

struct SelectionMessageScreen: View {
    let model: SelectionMessageModel

    var body: some View {
        NativeSelectionMessage(
            content: RefractSelectionContent(text: "读 🌸 docs", links: [
                RefractSelectionLink(range: RefractSelectionRange(start: 5, end: 9),
                                     destination: "https://example.test/docs"),
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
