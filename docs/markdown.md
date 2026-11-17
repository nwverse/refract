# Bounded typed Markdown and code blocks

`refractMarkdown` is a compile-time view contract for a small, versioned rich-text AST. It is **not** a Markdown
parser, a chat runtime, a streaming-message protocol or a full CommonMark implementation. The app may construct this
AST in its own native/shared code; a generated screen contains only literal AST construction accepted by the frontend.
No generated target parses Markdown, HTML or target-language strings at run time.

## Source and ownership

```swift
protocol ConversationModel: RefractModel {
    func openLink(_ url: String)
}

struct ConversationSnippet: View {
    let model: ConversationModel
    var body: some View {
        refractMarkdown(version: 1, blocks: [
            .paragraph(id: "answer.summary", content: [
                .localized("conversation.answer"),
                .strong(.localized("conversation.important")),
                .emphasis(.localized("conversation.note")),
                .inlineCode(verbatim: "let answer = 42"),
                .link(
                    label: .localized("conversation.docs"),
                    destination: .https(host: "example.com", path: "/docs")
                ),
            ]),
            .codeBlock(
                id: "answer.example",
                language: .swift,
                accessibilityLabel: .localized("conversation.code.label"),
                code: "func answer() -> Int {\n    return 42\n}\n"
            ),
        ], onLink: .linkAction(model.openLink))
    }
}
```

Version 1 accepts:

- A literal, nonempty array of at most 128 blocks. Every block has a distinct lowercase dotted source ID, such as
  `answer.summary`; an array index is not identity.
- Paragraphs with 1–128 inline values. `.localized` resolves a canonical key through the native resource catalogs;
  `.text(verbatim:)` is an intentional nonlocalized literal. Dynamic strings are rejected.
- `.strong` and `.emphasis` around ordinary text or inline code. They cannot wrap a link.
- `.inlineCode(verbatim:)` for a single line of at most 4096 UTF-8 bytes.
- At most one link per paragraph. A destination is a literal absolute HTTPS public DNS hostname and an ASCII path of
  at most 2048 UTF-8 bytes. Userinfo, IP literals, explicit ports, query, fragment, controls, backslashes and
  scheme-relative or non-HTTPS URLs are rejected. This is deliberately narrower than URL support in a chat product.
- A fenced-code equivalent: `.codeBlock` with `swift`, `kotlin` or `typescript` language metadata, a localized
  accessibility label, and nonempty literal code of at most 16384 UTF-8 bytes. No syntax highlighting is inferred.
  A newline is represented explicitly in the literal; it is not a markdown-source fence parsed later.

`onLink: .linkAction(model.openLink)` names a synchronous `String`-argument method on the declared model. The
frontend verifies the method signature and parameter label; it does not accept a stringly typed callback or arbitrary
closure. The app owns external-link confirmation, URL opening, selection, editing and AI-context behavior. Those
boundaries belong to #201, not this rendering contract.

## Native lowering

Compose directly emits `Column`, stable `key(id)` groups, `Text(buildAnnotatedString { ... })`, `SpanStyle`,
`FontFamily.Monospace` and `LinkAnnotation.Url`. Its listener invokes only the checked model action; it does not fall
through to `UriHandler`. Localized link labels and the code-block accessibility label are resolved in the enclosing
composable, not inside a non-composable semantics/building lambda. Code is a separate native monospace `Text`, with
its localized label attached through `semantics`, not merged into paragraph content or passed to a WebView.

ArkUI emits sibling `Span`s in a `Text`, with flat font attributes and `onClick` calling the same model action.
`Span` cannot contain children and does not accept `accessibilityText`, so nested styles are flattened during
lowering and accessibility stays on `Text`. Code is a separate monospace `Text` with `.accessibilityText`. Its
background uses the app-owned `app.color.markdown_code_background` resource, declared by the fixture. Native resource
merging and the ArkTS compiler check are not yet available. `monospace` is the native family name, not a promise of a particular font on every device.

iOS compiles the same Swift AST construction with the app-owned declarations in
`examples/ios/RefractExample/RefractMarkdownSource.swift`. They use native `AttributedString` attributes, not
`AttributedString(markdown:)` or another runtime Markdown parser. `OpenURLAction` forwards activation to the same
model method. These are source declarations in the iOS target, not a linked Refract framework or runtime registry.
The shared source is `examples/shared/MarkdownConversation.swift`, byte-identical to the canonical fixture.

## Diagnostics and non-goals

`RFMD001`–`RFMD018` cover the version, literal AST shape, bounds, IDs, text provenance, link destination, typed link
action and the one-link/style restrictions. Unsupported HTML, headings, lists, images, tables, arbitrary syntax
highlighting and runtime Markdown input fail at build time. They are never silently dropped or rendered approximately.
In particular, `blocks: model.markdown` is not a supported bridge from an app's dynamic document to this static view;
such a product needs its own typed native component or a separately reviewed dynamic-contract proposal.

This slice does not implement chat history, message models, streaming deltas, cursor/selection mapping, editing,
drag/drop, IME, link confirmation policy, syntax parsing or full Markdown. The link boundary remains intentionally
small so #201 can define selection and AI-edit context without coupling them to document generation.

## Verification evidence

- `Fixtures/markdown-conversation` regenerates both native outputs and compiles with the real Android fixture build.
- `GeneratedConversationMarkdownTest` runs the exact staged CLI output on Native JVM Compose with Robolectric. It
  checks the complete paragraph text, the link annotation and callback, and the separate code block/accessibility
  label. This is a JVM semantics test, not an emulator/device screenshot, browser-opening test or TalkBack proof.
  The fixture resource-staging helper trims XML text whitespace, so its expected concatenated paragraph reflects that
  test catalog; this is not a whitespace-preservation claim for arbitrary Android resource tooling.
- Rejected link, HTML and runtime-input fixtures assert source-located diagnostics. Unit tests pin the typed IR and
  the app-owned link method. `swift test` verifies deterministic dual-backend output, not ArkTS or SwiftUI compilation.
- The iOS project references the same source and its native source declarations. **Not verified on macOS**: no Apple
  compiler or simulator was available for this change. iOS compilation, link activation and accessibility require a
  real Apple-toolchain pass; the source contract is not presented as a verified simulator/device result.
- No HarmonyOS command-line compiler was available. ArkTS output is source evidence only. It has not been compiled,
  rendered or checked with a screen reader. The code-block color resource and final ArkUI accessibility behavior need
  an app-owned native integration check before production adoption.

The complete conversation fixture contains localized prose, bold and italic runs, inline code, a native HTTPS link,
and a multiline Swift code block. It is representative of this bounded renderer, not a claim of arbitrary Markdown
coverage or performance parity. There is no generated runtime library, start-up work, interpreter, HTML view or
benchmark claim in this slice.
