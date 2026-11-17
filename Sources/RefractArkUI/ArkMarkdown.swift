import RefractIR
import RefractMapping

extension Generation {
    func emitMarkdown(_ document: MarkdownDocument, linkAction: MarkdownLinkAction?, modifiers: [Modifier],
                      into writer: inout ArkWriter, mapping: Mapping) throws {
        guard document.version == MarkdownDocument.currentVersion, let linkAction,
              module.screens.flatMap(\.states).contains(where: { state in
                  guard case let .model(reference, _) = state,
                        reference.propertyName == linkAction.model,
                        let model = module.models.first(where: { $0.name == reference.protocolName }) else { return false }
                  return model.actions.contains {
                      $0.name == linkAction.method && $0.parameters.count == 1 &&
                          $0.parameters[0].type == .string && $0.parameters[0].externalName == linkAction.argumentLabel
                  }
              }) else {
            throw Diagnostic(code: "RFMD017", message: "ArkUI Markdown needs a checked model String link action.",
                             suggestion: "Pass `onLink: model.openLink`; the app owns link activation.")
        }
        writer.open("Column({ space: 8 })")
        for block in document.blocks {
            switch block {
            case let .paragraph(paragraph):
                writer.open("Text()")
                for inline in paragraph.content {
                    try emitMarkdownInline(inline, action: linkAction, into: &writer, mapping: mapping)
                }
                writer.close(suffix: ".accessibilityText('markdown.\(paragraph.id)')")
            case let .codeBlock(code):
                writer.line("Text('\(arkMarkdownLiteral(code.code))')")
                writer.line(".fontFamily('monospace')")
                writer.line(".padding(12)")
                writer.line(".backgroundColor($r('app.color.markdown_code_background'))")
                writer.line(".accessibilityText(\(try ArkExpression.emit(Expression(.localizedText(code.accessibilityLabel)), mapping: mapping)))")
                writer.line(".id('markdown.\(code.id)')")
            }
        }
        writer.close(suffix: try ArkModifiers.emit(modifiers, mapping: mapping))
    }

    private func emitMarkdownInline(_ inline: MarkdownDocument.Inline, action: MarkdownLinkAction,
                                    into writer: inout ArkWriter, mapping: Mapping) throws {
        switch inline {
        case let .text(expression):
            writer.line("Span(\(try ArkExpression.emit(expression, mapping: mapping)))")
        case let .strong(value), let .emphasis(value):
            let isStrong: Bool
            if case .strong = inline { isStrong = true } else { isStrong = false }
            // ArkUI Span has no child component support. Flatten typed nested styles to a leaf.
            try emitMarkdownSpan(value, style: isStrong ? ".fontWeight(FontWeight.Bold)" : ".fontStyle(FontStyle.Italic)",
                                 action: action, into: &writer, mapping: mapping)
        case let .inlineCode(code):
            writer.line("Span('\(arkMarkdownLiteral(code))')")
            writer.line(".fontFamily('monospace')")
        case let .link(link):
            let url = "\(link.destination.scheme)://\(link.destination.host)\(link.destination.path)"
            writer.line("Span(\(try ArkExpression.emit(link.label, mapping: mapping)))")
            writer.line(".fontColor(Color.Blue)")
            writer.line(".decoration({ type: TextDecorationType.Underline })")
            writer.open(".onClick(() =>")
            let label = action.argumentLabel.map { "\($0): " } ?? ""
            writer.line("this.\(action.model).\(action.method)(\(label)'\(arkMarkdownLiteral(url))');")
            writer.close(suffix: ")")
        }
    }

    private func emitMarkdownSpan(_ inline: MarkdownDocument.Inline, style: String, action: MarkdownLinkAction,
                                  into writer: inout ArkWriter, mapping: Mapping) throws {
        switch inline {
        case let .text(expression):
            writer.line("Span(\(try ArkExpression.emit(expression, mapping: mapping)))\(style)")
        case let .inlineCode(code):
            writer.line("Span('\(arkMarkdownLiteral(code))')\(style).fontFamily('monospace')")
        case let .strong(value), let .emphasis(value):
            try emitMarkdownSpan(value, style: style, action: action, into: &writer, mapping: mapping)
        case .link:
            throw Diagnostic(code: "RFMD018", message: "A styled link requires a link-level style contract on ArkUI.",
                             suggestion: "Put `.strong` or `.emphasis` inside ordinary text, not around `.link`.")
        }
    }
}

private func arkMarkdownLiteral(_ value: String) -> String {
    var result = ""
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\\": result += "\\\\"
        case "'": result += "\\'"
        case "\n": result += "\\n"
        case "\r": result += "\\r"
        case "\t": result += "\\t"
        case "$": result += "\\$"
        default:
            if scalar.value < 0x20 || scalar.value == 0x7f {
                result += String(format: "\\u{%X}", scalar.value)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
    }
    return result
}
