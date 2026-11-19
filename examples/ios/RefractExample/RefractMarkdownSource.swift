import SwiftUI

// The iOS-owned source contract. This structural renderer has no Markdown parser or Refract dependency.
public enum RefractMarkdownBlock {
    case paragraph(id: String, content: [RefractMarkdownInline])
    case codeBlock(id: String, language: RefractMarkdownLanguage, accessibilityLabel: LocalizedStringKey, code: String)
}

public indirect enum RefractMarkdownInline {
    case localized(LocalizedStringKey)
    case text(verbatim: String)
    case strong(RefractMarkdownInline)
    case emphasis(RefractMarkdownInline)
    case inlineCode(verbatim: String)
    case link(label: RefractMarkdownInline, destination: RefractMarkdownDestination)
}

public enum RefractMarkdownDestination {
    case https(host: String, path: String)

    fileprivate var url: URL? {
        switch self {
        case let .https(host, path): URL(string: "https://\(host)\(path)")
        }
    }
}

public enum RefractMarkdownLanguage {
    case swift, kotlin, typescript
}

/// Explicit source ownership; the generator accepts only a checked model String method reference.
public struct RefractMarkdownLinkAction {
    let handler: (String) -> Void
}

public func linkAction(_ handler: @escaping (String) -> Void) -> RefractMarkdownLinkAction {
    RefractMarkdownLinkAction(handler: handler)
}

private struct RefractMarkdownParagraph: View {
    let content: [RefractMarkdownInline]
    let onLink: (String) -> Void

    var body: some View {
        Text(content.reduce(into: AttributedString()) { result, inline in
            result.append(attributed(inline))
        })
        .environment(\.openURL, OpenURLAction { url in
            onLink(url.absoluteString)
            return .handled
        })
    }

    private func attributed(_ inline: RefractMarkdownInline) -> AttributedString {
        switch inline {
        case let .localized(key):
            AttributedString(String(localized: key))
        case let .text(text):
            AttributedString(text)
        case let .strong(value):
            var result = attributed(value)
            result.inlinePresentationIntent = .stronglyEmphasized
            return result
        case let .emphasis(value):
            var result = attributed(value)
            result.inlinePresentationIntent = .emphasized
            return result
        case let .inlineCode(code):
            var result = AttributedString(code)
            result.font = .system(.body, design: .monospaced)
            return result
        case let .link(label, destination):
            var result = attributed(label)
            result.link = destination.url
            result.foregroundColor = .accentColor
            result.underlineStyle = .single
            return result
        }
    }
}

private struct RefractMarkdownBlockView: View {
    let block: RefractMarkdownBlock
    let onLink: (String) -> Void

    var body: some View {
        switch block {
        case let .paragraph(id, content):
            RefractMarkdownParagraph(content: content, onLink: onLink)
                .accessibilityIdentifier("markdown.\(id)")
        case let .codeBlock(id, _, accessibilityLabel, code):
            Text(verbatim: code)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier("markdown.\(id)")
        }
    }
}

/// The generator accepts only static literals in this call. The iOS view consumes the same typed values directly.
@ViewBuilder
public func refractMarkdown(
    version: Int,
    blocks: [RefractMarkdownBlock],
    onLink: RefractMarkdownLinkAction
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(blocks.enumerated()), id: \.element.stableID) { _, block in
            RefractMarkdownBlockView(block: block, onLink: onLink.handler)
        }
    }
}

private extension RefractMarkdownBlock {
    var stableID: String {
        switch self {
        case let .paragraph(id, _): id
        case let .codeBlock(id, _, _, _): id
        }
    }
}
