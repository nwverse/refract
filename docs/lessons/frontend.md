# SwiftSyntax frontend

- SwiftParser leaves unparenthesized comparison/boolean chains as a flat `SequenceExprSyntax`, not an
  `InfixOperatorExprSyntax`. A bounded filter/sort grammar must check the exact element count and every operator/member
  position. Do not broaden it to arbitrary expressions; print the real AST once, then preserve the negative cases.

- Unknown accessor or signature "effects" such as `{ get refractText }` or `func f() refractAsync` are not syntax
  SwiftParser accepts: they produce a recovered tree with `UnexpectedNodesSyntax`, so the source can never be valid
  SwiftUI. Compile-time-only markers belong in custom attributes (`@refractText`, `@refractAsync`), which parse
  cleanly as `AttributeSyntax` and leave the iOS type checker to the app's own declarations.
- `.equals("confirmation")` in a trailing-closure rule list parses as a `FunctionCallExprSyntax` whose callee is the
  argument-free `MemberAccessExprSyntax` `.equals`; the literal is the call's own argument, not a
  `DeclNameArgumentSyntax`. `DeclNameArgumentSyntax` holds only argument *names* (`name:`, `name::`), never values.
- `Form { ... } (form: $form)` reaches the frontend as one `FunctionCallExprSyntax` whose called expression is the
  inner `Form { ... }` call, exactly like a modifier chain. Dispatch on the inner callee before the generic
  "reclassify the outer trailing closure" path, or the view falls through to the design-system/native diagnostics.
- An optional model text rendered as `Text(model.error)` cannot smart-cast `State<String?>.value` in Kotlin: the
  property has an open getter. Emit `?: ""` at the text leaf only; never rebind it into a screen-level local, which
  would break narrow observation.

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
- Repeated generated View, model, item or enum names are ambiguous even in one file. Diagnose them before walking
  the tree, but finish the ordinary traversal so independent source errors are retained. Discard partial IR afterward
  rather than returning early, which would suppress valid model-input diagnostics. Keep cross-file resolution separate.
- Resolve multi-file declarations from an explicit input set, not from a global cache or directory scan. Keep the
  complete type catalog separate from each file's emitted declarations: a model may reference an item from another
  file without emitting a duplicate class. When adding a multi-input overload, label the parameter (`parse(sources:)`)
  so an array literal cannot silently select the existing single-file overload.
- A model-backed text `Binding` must tie the getter and setter to the same logical property, not merely to any String
  action on the model. Otherwise `get: { model.otherText }` can silently write `searchText`. The closed
  `set<Property>` convention, owner/type/label checks and a mismatched-property negative test keep this source path
  faithful without inventing a writable projection on a get-only protocol.
- Nested typed scopes need an explicit owner. A message row and its block can have distinct identities even when their
  Swift closure parameters have the same spelling. Capture the checked parent when entering `ForEach(message.blocks)`,
  initialize the block declaration's scope before parsing its body, and restore both scopes on exit. Parsing the child
  call twice in different scopes produces misleading duplicate diagnostics. Do not pass arbitrary sibling item values
  through the general single-item `ChildView` path.
