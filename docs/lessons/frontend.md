# SwiftSyntax frontend

- Do not call `swift run` from a test process running in that same package: nested SwiftPM invocations can wait on
  the package build lock. Build the executable first, locate it beside `CommandLine.arguments[0]` (the per-target
  test-runner executable, not `Bundle.main`), and run that binary directly.
- `SyntaxVisitor` is a class, not a value-type visitor: collect diagnostics on a final reference type and qualify
  the IR's `SourceLocation` where it collides with SwiftSyntax's type. Do not silently discard a source coordinate.
- Parse body shape separately from its expression. Otherwise a known rejection such as `Image` produces a redundant
  `unsupportedViewBody` after the useful `unsupportedView` diagnostic. A rejected subtree returns no IR, so the
  outer structural check must not report it again.
- SwiftSyntax 600.0.1 represents `$property` as a `DeclReferenceExprSyntax` whose base name includes `$`, not as a
  `PrefixOperatorExprSyntax`. Accept a projection only at a supported binding argument, validate the declaration's
  ownership and type, and never accept an arbitrary projected string as a writable value.
- Avoid shadowing a `location(of:)` helper with a local `location`; it makes later source-coordinate lookups attempt
  to call the local value.
- Generated backend output is not an error channel. A backend with an unsupported IR node throws the shared typed
  `Diagnostic`; it never emits a comment that looks like successful output.
- SwiftParser always returns a recovery tree, including for malformed input. Before visiting it, check `tree.hasError`
- In SwiftSyntax 600, a view expression can be an `ExprSyntax` directly, while a root `if` or `switch` can be
  wrapped in `ExpressionStmtSyntax`. Dispatch builder statements through both shapes and keep `#if` on its existing
  `IfConfigDeclSyntax` path; a single `as(ExprSyntax.self)` assumption rejects valid view-builder control flow.
- SwiftParser always returns a recovery tree, including for malformed input. Before visiting it, check `tree.hasError`
  and convert `SwiftParserDiagnostics.ParseDiagnosticsGenerator.diagnostics(for:)` errors into `RFSYN001` with their
  source positions. On the pinned `600.0.1` release the implementation is `ParseDiagnosticsGenerator`, not an API named
  `ParserDiagnosticsEngine`. Importing `SwiftDiagnostics` introduces another `Diagnostic` type, so qualify the IR type.
- Never build IR from a recovered malformed tree: the recovery may look valid enough to emit plausible but wrong code.
- A supported `body` does not make every sibling declaration valid. Before selecting the typed-input or state/model
  parsing path, reject methods, initializers, nested types and arbitrary computed/observed properties with `RFSYN004`.
  Let the specialized parsers retain their diagnostics for malformed `@State`, `@Binding` and model inputs rather than
  replacing those codes with a generic declaration error.
