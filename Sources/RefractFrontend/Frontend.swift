import RefractIR
import SwiftParser
import SwiftSyntax

public struct Frontend {
    public init() {}

    public static func parse(_ source: SourceFile) -> TranslationUnit {
        let tree = Parser.parse(source: source.contents)
        let builder = Builder(file: source.path, tree: tree)
        builder.walk(tree)
        return TranslationUnit(module: Module(sourceFile: source.path, screens: builder.screens),
                               diagnostics: builder.diagnostics)
    }
}

private final class Builder: SyntaxVisitor {
    let file: String
    let converter: SourceLocationConverter
    var screens: [Screen] = []
    var diagnostics: [Diagnostic] = []

    init(file: String, tree: SourceFileSyntax) {
        self.file = file
        self.converter = SourceLocationConverter(fileName: file, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.inheritanceClause?.inheritedTypes.contains(where: {
            $0.type.trimmedDescription == "View"
        }) == true else { return .skipChildren }

        guard node.memberBlock.members.count == 1,
            let body = node.memberBlock.members.first?.decl.as(VariableDeclSyntax.self),
            body.bindings.count == 1,
            let binding = body.bindings.first,
            binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "body",
            let accessors = binding.accessorBlock?.accessors,
            case let .getter(items) = accessors else {
            error("unsupportedViewBody", "A View must have one expression-bodied `body` getter and no stored properties yet.",
                  "Return a supported view from `body`.", at: node.name)
            return .skipChildren
        }
        guard let expression = expression(in: items) else {
            error("unsupportedViewBody", "The `body` getter must return exactly one view expression.",
                  "Return a supported view from `body`.", at: binding.pattern)
            return .skipChildren
        }
        guard let root = view(expression) else { return .skipChildren }

        screens.append(Screen(name: node.name.text, body: root, location: location(of: node.name)))
        return .skipChildren
    }

    private func view(_ expression: ExprSyntax) -> ViewNode? {
        if let call = expression.as(FunctionCallExprSyntax.self) {
            return view(call)
        }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base {
            guard let node = view(base) else { return nil }
            return modifier(member, on: node)
        }
        error("unsupportedExpression", "The expression `\(expression.trimmedDescription)` is not a supported view.",
              "Use VStack, HStack, Text, or Button.", at: expression)
        return nil
    }

    private func modifier(_ member: MemberAccessExprSyntax, on node: ViewNode) -> ViewNode? {
        let name = member.declName.baseName.text
        guard name == "padding", member.declName.argumentNames == nil else {
            error("unsupportedModifier", "The modifier `\(name)` is not supported.",
                  "Use a supported subset modifier.", at: member)
            return nil
        }
        switch node {
        case let .stack(axis, children, modifiers, location):
            return .stack(axis: axis, children: children, modifiers: modifiers + [Modifier(name: name)], location: location)
        case let .text(expression, modifiers, location):
            return .text(expression, modifiers: modifiers + [Modifier(name: name)], location: location)
        case let .button(label, action, modifiers, location):
            return .button(label: label, action: action, modifiers: modifiers + [Modifier(name: name)], location: location)
        case .native, .conditional:
            error("unsupportedModifierTarget", "This modifier target is not supported yet.", at: member)
            return nil
        }
    }

    private func view(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) else {
            error("unsupportedView", "This view call is not supported.",
                  "Use VStack, HStack, Text, or Button.", at: call)
            return nil
        }
        let name = reference.baseName.text
        let nodeLocation = location(of: call)
        switch name {
        case "VStack", "HStack":
            guard call.arguments.isEmpty, let children = children(of: call.trailingClosure) else {
                error("unsupportedViewArguments", "\(name) supports only an unlabeled child closure.", at: call)
                return nil
            }
            return .stack(axis: name == "VStack" ? .vertical : .horizontal,
                          children: children, modifiers: [], location: nodeLocation)
        case "Text":
            guard call.arguments.count == 1, call.arguments.first?.label == nil,
                  let argument = call.arguments.first?.expression,
                  let string = stringLiteral(argument), call.trailingClosure == nil else {
                error("unsupportedText", "Text requires one unlabeled string literal.",
                      "Use Text(\"literal\") in this version.", at: call)
                return nil
            }
            return .text(Expression(.stringLiteral(string), location: location(of: argument)),
                         modifiers: [], location: nodeLocation)
        case "Button":
            guard call.arguments.count == 1, call.arguments.first?.label == nil,
                  let argument = call.arguments.first?.expression,
                  let labelText = stringLiteral(argument),
                  call.additionalTrailingClosures.isEmpty else {
                error("unsupportedButton", "Button requires one string-literal title and an empty action.",
                      "Use Button(\"title\") { }.", at: call)
                return nil
            }
            if let action = call.trailingClosure, !action.statements.isEmpty {
                error("unsupportedButtonAction", "Button actions are not supported by this version.",
                      "Use an empty action until model actions are available.", at: action)
                return nil
            }
            let label = ViewNode.text(Expression(.stringLiteral(labelText)), modifiers: [], location: nodeLocation)
            return .button(label: label, action: nil, modifiers: [], location: nodeLocation)
        default:
            error("unsupportedView", "`\(name)` is not in the supported view subset.",
                  "Use VStack, HStack, Text, or Button.", at: call)
            return nil
        }
    }

    private func children(of closure: ClosureExprSyntax?) -> [ViewNode]? {
        guard let closure else { return [] }
        var result: [ViewNode] = []
        for item in closure.statements {
            guard let expression = item.item.as(ExprSyntax.self) else {
                error("unsupportedStatement", "Only view expressions are allowed in a view builder.",
                      "Remove local statements or move them behind a model.", at: item)
                return nil
            }
            guard let child = view(expression) else { return nil }
            result.append(child)
        }
        return result
    }

    private func expression(in items: CodeBlockItemListSyntax) -> ExprSyntax? {
        guard items.count == 1, let item = items.first else { return nil }
        if let expression = item.item.as(ExprSyntax.self) { return expression }
        return item.item.as(ReturnStmtSyntax.self)?.expression
    }

    private func stringLiteral(_ expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self), literal.segments.count == 1,
            case let .stringSegment(segment)? = literal.segments.first else { return nil }
        return segment.content.text
    }

    private func location(of node: some SyntaxProtocol) -> RefractIR.SourceLocation {
        let position = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        return RefractIR.SourceLocation(file: file, line: position.line, column: position.column)
    }

    private func error(_ code: String, _ message: String, _ suggestion: String? = nil,
                       at node: some SyntaxProtocol) {
        diagnostics.append(Diagnostic(code: code, message: message, suggestion: suggestion,
                                      location: location(of: node)))
    }
}
