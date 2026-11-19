import RefractIR
import SwiftSyntax

/// Parses only literal, versioned rich-text AST construction. It never parses a Markdown source string.
extension Builder {
    func markdownDocument(_ call: FunctionCallExprSyntax) -> ViewNode? {
        let location = location(of: call)
        guard call.additionalTrailingClosures.isEmpty, call.trailingClosure == nil,
              call.arguments.map(\.label?.text) == ["version", "blocks", "onLink"],
              let action = markdownLinkAction(call.arguments.last!) else {
            error("RFMD001", "`refractMarkdown` requires exactly `version: 1, blocks: [...], onLink: model.action` and no closure.",
                  "Use a literal, versioned AST of `.paragraph` and `.codeBlock` values.", at: call)
            return nil
        }
        let arguments = Array(call.arguments)
        guard arguments[0].expression.as(IntegerLiteralExprSyntax.self)?.literal.text == "1" else {
            error("RFMD002", "Only static Markdown AST version 1 is supported.",
                  "Use `version: 1`; do not pass a dynamic document or Markdown source string.", at: arguments[0].expression)
            return nil
        }
        guard let values = arguments[1].expression.as(ArrayExprSyntax.self)?.elements else {
            error("RFMD003", "Markdown blocks must be a literal, nonempty array of typed blocks.",
                  "Construct `.paragraph(id:content:)` and `.codeBlock(id:language:accessibilityLabel:code:)` values at build time.", at: arguments[1].expression)
            return nil
        }
        guard !values.isEmpty, values.count <= 128 else {
            error("RFMD004", "A bounded Markdown document has between 1 and 128 blocks.",
                  "Split a longer document into separate, app-owned views.", at: arguments[1].expression)
            return nil
        }
        var blocks: [MarkdownDocument.Block] = []
        var identities = Set<String>()
        for element in values {
            guard let call = element.expression.as(FunctionCallExprSyntax.self),
                  let block = markdownBlock(call, identities: &identities) else { return nil }
            blocks.append(block)
        }
        return .markdown(MarkdownDocument(version: 1, blocks: blocks), linkAction: action, modifiers: [], location: location)
    }

    private func markdownLinkAction(_ argument: LabeledExprSyntax) -> MarkdownLinkAction? {
        guard let call = argument.expression.as(FunctionCallExprSyntax.self),
              let wrapper = call.calledExpression.as(MemberAccessExprSyntax.self), wrapper.base == nil,
              wrapper.declName.baseName.text == "linkAction", wrapper.declName.argumentNames == nil,
              call.trailingClosure == nil, call.arguments.count == 1, call.arguments.first?.label == nil,
              let methodReference = call.arguments.first?.expression,
              let member = methodReference.as(MemberAccessExprSyntax.self),
              let base = member.base?.as(DeclReferenceExprSyntax.self) else {
            error("RFMD017", "`onLink` must name a declared model action accepting exactly one String URL.",
                  "Use `.linkAction(model.openLink)`.", at: argument.expression)
            return nil
        }
        guard let owner = currentModels.first(where: { $0.propertyName == base.baseName.text }),
              let model = models.first(where: { $0.name == owner.protocolName }),
              let action = model.actions.first(where: { $0.name == member.declName.baseName.text }),
              action.parameters.count == 1, action.parameters[0].type == .string else {
            error("RFMD017", "`onLink` must name a declared model action accepting exactly one String URL.",
                  "Declare `func openLink(_ url: String)` on the model and pass `onLink: .linkAction(model.openLink)`; the app owns URL activation.", at: argument.expression)
            return nil
        }
        return MarkdownLinkAction(model: owner.propertyName, method: action.name,
                                  argumentLabel: action.parameters[0].externalName)
    }

    private func markdownBlock(_ call: FunctionCallExprSyntax,
                               identities: inout Set<String>) -> MarkdownDocument.Block? {
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self), member.base == nil,
              call.additionalTrailingClosures.isEmpty, call.trailingClosure == nil else {
            error("RFMD005", "Markdown block must be a typed `.paragraph` or `.codeBlock` literal.",
                  "HTML, lists, images, headings and arbitrary view/source payloads are not supported.", at: call)
            return nil
        }
        let arguments = Array(call.arguments)
        switch member.declName.baseName.text {
        case "paragraph":
            guard arguments.map(\.label?.text) == ["id", "content"],
                  let id = markdownIdentifier(arguments[0].expression, identities: &identities),
                  let values = arguments[1].expression.as(ArrayExprSyntax.self)?.elements,
                  !values.isEmpty, values.count <= 128 else {
                error("RFMD006", "A paragraph needs a unique stable `id` and 1 to 128 literal inline nodes.",
                      "Use `.paragraph(id: \"answer.summary\", content: [...])` with a lowercase dotted identity.", at: call)
                return nil
            }
            var content: [MarkdownDocument.Inline] = []
            var linkCount = 0
            for element in values {
                if markdownContainsLink(element.expression) { linkCount += 1 }
                guard let value = markdownInline(element.expression) else { return nil }
                content.append(value)
            }
            guard linkCount <= 1 else {
                error("RFMD018", "Version 1 permits at most one link per paragraph.",
                      "Split links into separately identified paragraphs; selection and compound-link context belong to #201.", at: call)
                return nil
            }
            return .paragraph(MarkdownDocument.Paragraph(id: id, content: content, location: location(of: call)))
        case "codeBlock":
            guard arguments.map(\.label?.text) == ["id", "language", "accessibilityLabel", "code"],
                  let id = markdownIdentifier(arguments[0].expression, identities: &identities) else {
                error("RFMD007", "A code block requires `id`, `language`, `accessibilityLabel` and `code` in that order.",
                      "Use a literal language, localized label and verbatim literal code; syntax highlighting is not inferred.", at: call)
                return nil
            }
            guard let languageReference = arguments[1].expression.as(MemberAccessExprSyntax.self),
                  languageReference.base == nil,
                  let language = MarkdownDocument.Language(rawValue: languageReference.declName.baseName.text) else {
                error("RFMD007", "Code-block language must be one of `.swift`, `.kotlin` or `.typescript`.",
                      "Declare a supported language; do not pass source text to a syntax highlighter.", at: arguments[1].expression)
                return nil
            }
            guard let label = localizedMarkdownText(arguments[2].expression) else { return nil }
            guard let code = markdownLiteral(arguments[3].expression, label: "code"),
                  !code.isEmpty, code.utf8.count <= 16_384, !code.contains("\0") else {
                error("RFMD008", "Code must be a nonempty verbatim literal of at most 16384 UTF-8 bytes.",
                      "Use `verbatim: \"...\"`; preserve newlines explicitly and omit null characters.", at: arguments[3].expression)
                return nil
            }
            return .codeBlock(MarkdownDocument.CodeBlock(id: id, language: language, accessibilityLabel: label,
                                                        code: code, location: location(of: call)))
        default:
            error("RFMD005", "Markdown block `\(member.declName.baseName.text)` is outside version 1.",
                  "Use `.paragraph` or `.codeBlock`; unsupported structures are never dropped or converted to HTML.", at: call)
            return nil
        }
    }

    private func markdownContainsLink(_ expression: ExprSyntax) -> Bool {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self) else { return false }
        if member.declName.baseName.text == "link" { return true }
        return call.arguments.contains { markdownContainsLink($0.expression) }
    }

    private func markdownInline(_ expression: ExprSyntax) -> MarkdownDocument.Inline? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self), member.base == nil,
              call.additionalTrailingClosures.isEmpty, call.trailingClosure == nil else {
            error("RFMD009", "An inline node must be one of the typed version 1 constructors.",
                  "Use `.text`, `.strong`, `.emphasis`, `.inlineCode` or `.link`; nested images and HTML are not accepted.", at: expression)
            return nil
        }
        let arguments = Array(call.arguments)
        switch member.declName.baseName.text {
        case "text", "localized":
            let argument = LabeledExprSyntax(label: nil, colon: nil, expression: ExprSyntax(call), trailingComma: nil)
            guard arguments.count == 1, let text = markdownText(argument) else { return nil }
            return .text(text)
        case "strong", "emphasis":
            guard arguments.count == 1, arguments[0].label == nil,
                  !markdownContainsLink(arguments[0].expression),
                  let value = markdownInline(arguments[0].expression) else {
                error("RFMD010", "Strong and emphasis accept one plain text or code inline, never a link.",
                      "Compose `.strong(.text(...))` or `.emphasis(.text(...))`; do not embed a view.", at: call)
                return nil
            }
            return member.declName.baseName.text == "strong" ? .strong(value) : .emphasis(value)
        case "inlineCode":
            guard arguments.map(\.label?.text) == ["verbatim"],
                  let text = markdownLiteral(arguments[0].expression, label: "inline code"),
                  !text.isEmpty, text.utf8.count <= 4096, !text.contains(where: \.isNewline), !text.contains("\0") else {
                error("RFMD011", "Inline code needs a nonempty, single-line `verbatim` literal of at most 4096 UTF-8 bytes.",
                      "Use `.inlineCode(verbatim: \"value\")`; line breaks belong in a code block.", at: call)
                return nil
            }
            return .inlineCode(text)
        case "link":
            guard arguments.map(\.label?.text) == ["label", "destination"],
                  let text = markdownText(arguments[0]),
                  let destination = markdownDestination(arguments[1].expression) else {
                error("RFMD012", "A link needs a plain `.localized(...)` or `.text(verbatim: ...)` label and a typed HTTPS destination.",
                      "Use `.link(label: ..., destination: .https(host: \"example.com\", path: \"/docs\"))`.", at: call)
                return nil
            }
            return .link(MarkdownDocument.Link(label: text, destination: destination, location: location(of: call)))
        default:
            error("RFMD009", "Markdown inline `\(member.declName.baseName.text)` is outside version 1.",
                  "Use `.text`, `.strong`, `.emphasis`, `.inlineCode` or `.link`.", at: call)
            return nil
        }
    }

    private func markdownText(_ argument: LabeledExprSyntax) -> Expression? {
        guard let call = argument.expression.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self), member.base == nil,
              call.trailingClosure == nil, call.arguments.count == 1 else {
            error("RFMD013", "Inline text must be `.localized(\"key\")` or `.text(verbatim: \"...\")`.",
                  "Declare localization explicitly; dynamic strings are not Markdown AST values.", at: argument.expression)
            return nil
        }
        switch member.declName.baseName.text {
        case "localized":
            guard call.arguments.first?.label == nil,
                  let key = stringLiteral(call.arguments.first!.expression), LocalizationKey.isCanonical(key) else {
                error("RFMD013", "A localized inline label needs a static canonical resource key.",
                      "Use lowercase dotted ASCII resource keys and declare them in both native catalogs.", at: call)
                return nil
            }
            return Expression(.localizedText(LocalizedText(key: key)), type: .string, location: location(of: call))
        case "text":
            guard call.arguments.first?.label?.text == "verbatim",
                  let text = markdownLiteral(call.arguments.first!.expression, label: "text") else {
                error("RFMD013", "Verbatim inline text must be one noninterpolated literal.",
                      "Use `.text(verbatim: \"...\")` for code and machine-generated literal text.", at: call)
                return nil
            }
            return Expression(.verbatimText(text), type: .string, location: location(of: call))
        default:
            error("RFMD013", "Inline text kind `\(member.declName.baseName.text)` is unsupported.",
                  "Use `.localized` for prose or `.text(verbatim:)` for intentional literal text.", at: call)
            return nil
        }
    }

    private func localizedMarkdownText(_ expression: ExprSyntax) -> LocalizedText? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(MemberAccessExprSyntax.self)?.base == nil,
              call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "localized",
              call.trailingClosure == nil, call.arguments.count == 1, call.arguments.first?.label == nil,
              let key = stringLiteral(call.arguments.first!.expression), LocalizationKey.isCanonical(key) else {
            error("RFMD014", "A code-block accessibility label must be `.localized(\"key\")`.",
                  "Provide a static localized resource key; do not expose raw code as its accessibility label.", at: expression)
            return nil
        }
        return LocalizedText(key: key)
    }

    private func markdownDestination(_ expression: ExprSyntax) -> MarkdownDocument.Destination? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(MemberAccessExprSyntax.self)?.base == nil,
              call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "https",
              call.trailingClosure == nil, call.arguments.map(\.label?.text) == ["host", "path"],
              let host = stringLiteral(call.arguments.first!.expression),
              let path = stringLiteral(call.arguments.last!.expression) else {
            error("RFMD015", "Link destination must be a literal `.https(host:path:)` declaration.",
                  "Use an absolute HTTPS host and path; activation and external-navigation policy belong to the link boundary.", at: expression)
            return nil
        }
        guard isBoundedHTTPSHost(host), path.hasPrefix("/"), !path.hasPrefix("//"), path.utf8.count <= 2048,
              !path.contains(where: { $0 == "?" || $0 == "#" || $0 == "\\" || $0 == "@" || $0 == ":" || $0.isWhitespace || $0.isNewline }),
              !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else {
            error("RFMD015", "The HTTPS link destination is outside the bounded public-address syntax.",
                  "Use a public DNS hostname, port 443 and an ASCII path without userinfo, query, fragment or control characters.", at: expression)
            return nil
        }
        return MarkdownDocument.Destination(scheme: "https", host: host, path: path)
    }

    private func markdownIdentifier(_ expression: ExprSyntax, identities: inout Set<String>) -> String? {
        guard let id = stringLiteral(expression), LocalizationKey.isCanonical(id), identities.insert(id).inserted else {
            error("RFMD006", "Every Markdown block needs a distinct lowercase dotted source identity.",
                  "Use stable identifiers such as `answer.summary` and `answer.example`; do not use array indices.", at: expression)
            return nil
        }
        return id
    }

    private func markdownLiteral(_ expression: ExprSyntax, label: String) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self), !literal.segments.contains(where: {
            if case .stringSegment = $0 { return false }
            return true
        }) else {
            error("RFMD016", "Markdown \(label) must be a static string literal without interpolation.",
                  "Construct the AST at build time; runtime Markdown and arbitrary target strings are not supported.", at: expression)
            return nil
        }
        return literal.representedLiteralValue
    }

    private func isBoundedHTTPSHost(_ host: String) -> Bool {
        guard host.utf8.count <= 253, !host.hasPrefix("."), !host.hasSuffix(".") else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ label in
            guard label.count <= 63, let first = label.first, let last = label.last,
                  first.isASCII, first.isLetter || first.isNumber, last.isASCII, last.isLetter || last.isNumber else { return false }
            return label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }) else { return false }
        let numericLabels = labels.compactMap { UInt32($0) }
        if numericLabels.count == 4, numericLabels.allSatisfy({ $0 <= 255 }) { return false }
        return true
    }
}
