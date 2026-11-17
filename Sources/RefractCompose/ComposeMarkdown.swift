import RefractIR

extension ComposeBackend {
    func emitMarkdown(_ document: MarkdownDocument, linkAction: MarkdownLinkAction?, modifiers: [Modifier],
                      isRoot: Bool, location: SourceLocation?, into out: inout KotlinWriter,
                      context: inout Context) throws {
        guard document.version == MarkdownDocument.currentVersion, let linkAction,
              let model = context.module.models.first(where: { candidate in
                  context.module.screens.flatMap(\.states).contains { state in
                      guard case let .model(reference, _) = state else { return false }
                      return reference.propertyName == linkAction.model && reference.protocolName == candidate.name
                  }
              }), let method = model.actions.first(where: {
                  $0.name == linkAction.method && $0.parameters.count == 1 && $0.parameters[0].type == .string &&
                      $0.parameters[0].externalName == linkAction.argumentLabel
              }) else {
            throw Diagnostic(code: "RFMD017", message: "A generated Markdown document needs its checked String link action.",
                             suggestion: "Declare `func openLink(_ url: String)` on the model and pass `onLink: .linkAction(model.openLink)`.",
                             location: location)
        }
        let action: (String) -> String = { url in
            let label = method.parameters[0].externalName.map { "\($0) = " } ?? ""
            return "\(linkAction.model).\(linkAction.method)(\(label)\"\(url.escapedForKotlin())\")"
        }
        for item in [
            "androidx.compose.foundation.background", "androidx.compose.foundation.layout.Arrangement",
            "androidx.compose.foundation.layout.Column", "androidx.compose.foundation.layout.padding",
            "androidx.compose.material3.MaterialTheme", "androidx.compose.material3.Text", "androidx.compose.runtime.key",
            "androidx.compose.ui.semantics.contentDescription", "androidx.compose.ui.semantics.semantics",
            "androidx.compose.ui.text.LinkAnnotation", "androidx.compose.ui.text.SpanStyle",
            "androidx.compose.ui.text.TextLinkStyles", "androidx.compose.ui.text.buildAnnotatedString",
            "androidx.compose.ui.text.font.FontFamily", "androidx.compose.ui.text.font.FontStyle",
            "androidx.compose.ui.text.font.FontWeight", "androidx.compose.ui.text.style.TextDecoration",
            "androidx.compose.ui.text.withLink", "androidx.compose.ui.text.withStyle", "androidx.compose.ui.unit.dp",
        ] { context.imports.insert(item) }
        let chain = try modifierChain(modifiers, isRoot: isRoot, context: &context)
        out.open("Column(modifier = \(chain), verticalArrangement = Arrangement.spacedBy(8.dp))")
        for block in document.blocks {
            switch block {
            case let .paragraph(paragraph):
                try emitMarkdownParagraph(paragraph, action: action, into: &out, context: &context)
            case let .codeBlock(code):
                try emitMarkdownCodeBlock(code, into: &out, context: &context)
            }
        }
        out.close()
    }

    private func emitMarkdownParagraph(_ paragraph: MarkdownDocument.Paragraph,
                                       action: @escaping (String) -> String,
                                       into out: inout KotlinWriter, context: inout Context) throws {
        out.open("key(\"\(paragraph.id.escapedForKotlin())\")")
        for inline in paragraph.content {
            if case let .link(link) = inline {
                out.line("val linkLabel = \(try renderExpression(link.label, context: &context))")
            }
        }
        out.line("Text(")
        out.depth += 1
        out.line("text = buildAnnotatedString {")
        out.depth += 1
        out.line("pushStringAnnotation(tag = \"markdown.block\", annotation = \"\(paragraph.id.escapedForKotlin())\")")
        for inline in paragraph.content {
            try emitMarkdownInline(inline, action: action, into: &out, context: &context)
        }
        out.line("pop()")
        out.close(suffix: ",")
        out.depth -= 1
        out.line(")")
        out.close()
    }

    private func emitMarkdownInline(_ inline: MarkdownDocument.Inline, action: @escaping (String) -> String,
                                    into out: inout KotlinWriter, context: inout Context) throws {
        switch inline {
        case let .text(expression):
            out.line("append(\(try renderExpression(expression, context: &context)))")
        case let .strong(value), let .emphasis(value):
            let isStrong: Bool
            if case .strong = inline { isStrong = true } else { isStrong = false }
            out.open("withStyle(SpanStyle(\(isStrong ? "fontWeight = FontWeight.Bold" : "fontStyle = FontStyle.Italic")))")
            try emitMarkdownInline(value, action: action, into: &out, context: &context)
            out.close()
        case let .inlineCode(code):
            out.open("withStyle(SpanStyle(fontFamily = FontFamily.Monospace))")
            out.line("append(\"\(code.escapedForKotlin())\")")
            out.close()
        case let .link(link):
            let url = "\(link.destination.scheme)://\(link.destination.host)\(link.destination.path)"
            out.line("withLink(")
            out.depth += 1
            out.line("LinkAnnotation.Url(")
            out.depth += 1
            out.line("url = \"\(url.escapedForKotlin())\",")
            out.line("styles = TextLinkStyles(")
            out.depth += 1
            out.line("style = SpanStyle(color = MaterialTheme.colorScheme.primary, textDecoration = TextDecoration.Underline)")
            out.depth -= 1
            out.line("),")
            out.line("linkInteractionListener = { _ -> \(action(url)) }")
            out.depth -= 1
            out.line(")")
            out.depth -= 1
            out.line(") {")
            out.depth += 1
            out.line("append(linkLabel)")
            out.close()
        }
    }

    private func emitMarkdownCodeBlock(_ code: MarkdownDocument.CodeBlock,
                                       into out: inout KotlinWriter, context: inout Context) throws {
        let label = Expression(.localizedText(code.accessibilityLabel), type: .string, location: code.location)
        out.open("key(\"\(code.id.escapedForKotlin())\")")
        out.line("val codeAccessibilityLabel = \(try renderExpression(label, context: &context))")
        out.open("Text(")
        out.line("text = \"\(code.code.escapedForKotlin())\",")
        out.line("fontFamily = FontFamily.Monospace,")
        out.line("color = MaterialTheme.colorScheme.onSurfaceVariant,")
        out.line("modifier = Modifier")
        out.depth += 1
        out.line(".background(MaterialTheme.colorScheme.surfaceVariant)")
        out.line(".padding(12.dp)")
        out.line(".semantics { contentDescription = codeAccessibilityLabel },")
        out.depth -= 1
        out.depth -= 1
        out.line(")")
        out.close()
    }
}

private extension KotlinWriter {
    mutating func close(suffix: String) {
        depth -= 1
        line("}" + suffix)
    }
}
