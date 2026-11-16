import RefractIR
import SwiftParser
import SwiftSyntax

public struct Frontend {
    public init() {}

    public static func parse(_ source: SourceFile) -> TranslationUnit {
        let tree = Parser.parse(source: source.contents)
        let builder = Builder(file: source.path, tree: tree)
        builder.walk(tree)
        return TranslationUnit(module: Module(sourceFile: source.path, screens: builder.screens,
                                              nativeDeclarations: builder.interop.declarations),
                               diagnostics: builder.diagnostics)
    }
}

private final class Builder: SyntaxVisitor {
    let file: String
    let converter: SourceLocationConverter
    var screens: [Screen] = []
    var diagnostics: [Diagnostic] = []
    var interop: InteropFrontend

    init(file: String, tree: SourceFileSyntax) {
        self.file = file
        self.converter = SourceLocationConverter(fileName: file, tree: tree)
        self.interop = InteropFrontend(file: file, converter: converter)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if interop.declaration(node) {
            diagnostics.append(contentsOf: interop.takeDiagnostics())
            return .skipChildren
        }
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
            if items.contains(where: { $0.item.as(IfConfigDeclSyntax.self) != nil }) {
                return .visitChildren
            }
            error("unsupportedViewBody", "The `body` getter must return exactly one view expression.",
                  "Return a supported view from `body`.", at: binding.pattern)
            return .skipChildren
        }
        guard let root = view(expression) else { return .skipChildren }

        screens.append(Screen(name: node.name.text, body: root, location: location(of: node.name)))
        return .skipChildren
    }

    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        error("RFVIEW005", "Free-form conditional compilation hides platform-specific Swift code from the generator.",
              "Use `refractValue`, `refractView`, or a declared `RefractNativeView`", at: node.clauses)
        return .skipChildren
    }

    private func view(_ expression: ExprSyntax) -> ViewNode? {
        if let call = expression.as(FunctionCallExprSyntax.self) {
            // SwiftSyntax represents `Text("x").padding() { ... }` as a call whose called expression
            // is another call, not as a MemberAccessExprSyntax. Preserve the outer trailing closure
            // when classifying the inner call as a view or a modifier.
            if let base = call.calledExpression.as(FunctionCallExprSyntax.self) {
                var inner = base
                inner.trailingClosure = call.trailingClosure
                inner.additionalTrailingClosures = call.additionalTrailingClosures
                return view(inner)
            }
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base {
                guard let node = view(base) else { return nil }
                return modifier(call, name: member.declName.baseName.text, on: node)
            }
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

    private func modifier(_ call: FunctionCallExprSyntax, name: String, on node: ViewNode) -> ViewNode? {
        guard name == "padding", call.arguments.count <= 1, call.trailingClosure == nil else {
            error("unsupportedModifier", "The modifier `\(name)` is not supported.",
                  "Use a supported subset modifier.", at: call)
            return nil
        }
        var arguments: [Expression] = []
        if let argument = call.arguments.first {
            guard argument.label == nil, let value = scalar(argument.expression) else { return nil }
            arguments.append(value.expression)
        }
        return modifier(name, arguments: arguments, on: node, at: call)
    }

    private func modifier(_ member: MemberAccessExprSyntax, on node: ViewNode) -> ViewNode? {
        let name = member.declName.baseName.text
        guard name == "padding", member.declName.argumentNames == nil else {
            error("unsupportedModifier", "The modifier `\(name)` is not supported.",
                  "Use a supported subset modifier.", at: member)
            return nil
        }
        return modifier(name, arguments: [], on: node, at: member)
    }

    private func modifier(_ name: String, arguments: [Expression], on node: ViewNode,
                          at syntax: some SyntaxProtocol) -> ViewNode? {
        switch node {
        case let .stack(axis, children, modifiers, location):
            return .stack(axis: axis, children: children, modifiers: modifiers + [Modifier(name: name, arguments: arguments)], location: location)
        case let .text(expression, modifiers, location):
            return .text(expression, modifiers: modifiers + [Modifier(name: name, arguments: arguments)], location: location)
        case let .button(label, action, modifiers, location):
            return .button(label: label, action: action, modifiers: modifiers + [Modifier(name: name, arguments: arguments)], location: location)
        case .native, .conditional, .platformView:
            error("unsupportedModifierTarget", "This modifier target is not supported yet.", at: syntax)
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
        if name == "refractValue" {
            error("RFSEM001", "`refractValue` is a scalar expression, not a standalone view.",
                  "Use it inside a supported argument or modifier", at: call)
            return nil
        }
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
            guard call.arguments.count == 1,
                  let argument = call.arguments.first, call.trailingClosure == nil,
                  let value = scalar(argument.expression), value.type == .string,
                  (argument.label == nil) || (argument.label?.text == "verbatim") else {
                error("unsupportedText", "Text requires one string value, optionally labeled `verbatim`.",
                      "Use Text(\"key\") or Text(verbatim: \"literal\")", at: call)
                return nil
            }
            return .text(value.expression, modifiers: [], location: nodeLocation)
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
        case "refractView":
            return platformView(call)
        default:
            guard interop.declarations.contains(where: { $0.name == name }) else {
                let component = NativeComponent(name: name)
                diagnostics.append(contentsOf: interop.validate(component, declaration: nil, location: nodeLocation))
                return nil
            }
            guard !interop.invalidDeclarations.contains(name) else { return nil }
            let component = nativeComponent(call)
            guard let declaration = interop.declarations.first(where: { $0.name == name }) else { return nil }
            diagnostics.append(contentsOf: interop.validate(component, declaration: declaration, location: nodeLocation))
            return .native(component, location: nodeLocation)
        }
    }

    private func nativeComponent(_ call: FunctionCallExprSyntax) -> NativeComponent {
        let name = call.calledExpression.trimmedDescription
        let arguments = call.arguments.compactMap { argument -> NativeArgument? in
            guard let label = argument.label?.text, let value = scalar(argument.expression) else {
                error("RFNATIVE002", "Native component arguments require explicit labels and supported scalar values.",
                      "Use the memberwise SwiftUI initializer signature", at: argument)
                return nil
            }
            return NativeArgument(label: label, expression: value.expression, type: value.type,
                                  location: location(of: argument))
        }
        return NativeComponent(name: name, arguments: arguments)
    }

    private func platformView(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.map(\.label?.text) == ["ios", "android", "harmonyOS"] else {
            error("RFNATIVE003", "`refractView` requires exactly `ios`, `android`, and `harmonyOS` view-builder closures.",
                  "Supply all three typed platform view branches", at: call)
            return nil
        }
        var branches: [[ViewNode]] = []
        for argument in call.arguments {
            guard let closure = argument.expression.as(ClosureExprSyntax.self),
                  let children = children(of: closure) else {
                error("RFSEM001", "A platform view branch must contain only supported view expressions.",
                      "Use a supported view subtree or declared native component", at: argument)
                return nil
            }
            branches.append(children)
        }
        return .platformView(PlatformAlternatives(ios: branches[0], android: branches[1], harmonyOS: branches[2]),
                             location: location(of: call))
    }

    private func scalar(_ expression: ExprSyntax) -> TypedExpression? {
        if let string = stringLiteral(expression) {
            return TypedExpression(Expression(.stringLiteral(string), location: location(of: expression)), .string)
        }
        if let literal = expression.as(BooleanLiteralExprSyntax.self) {
            return TypedExpression(Expression(.boolLiteral(literal.literal.tokenKind == .keyword(.true)),
                                             location: location(of: expression)), .bool)
        }
        if let literal = expression.as(IntegerLiteralExprSyntax.self) {
            return TypedExpression(Expression(.numberLiteral(literal.literal.text),
                                             location: location(of: expression)), .int)
        }
        if let literal = expression.as(FloatLiteralExprSyntax.self) {
            return TypedExpression(Expression(.numberLiteral(literal.literal.text),
                                             location: location(of: expression)), .double)
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            // Ownership of model/state references is refined by the state frontend. Native declarations still
            // retain their expected source types rather than accepting an arbitrary untyped expression.
            return TypedExpression(Expression(.reference(reference.baseName.text),
                                             location: location(of: expression)), nil)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "refractValue" {
            return platformValue(call)
        }
        error("RFSEM001", "The expression `\(expression.trimmedDescription)` is not a supported scalar value.",
              "Use a supported literal, typed property, or `refractValue`", at: expression)
        return nil
    }

    private func platformValue(_ call: FunctionCallExprSyntax) -> TypedExpression? {
        guard call.arguments.map(\.label?.text) == ["ios", "android", "harmonyOS"] else {
            error("RFNATIVE003", "`refractValue` requires exactly `ios`, `android`, and `harmonyOS` arguments with compatible types.",
                  "Supply all three typed platform values", at: call)
            return nil
        }
        var values: [Expression] = []
        var type: ValueType?
        for argument in call.arguments {
            guard let value = scalar(argument.expression) else { return nil }
            if let type, let other = value.type, type != other {
                error("RFNATIVE003", "`refractValue` branches have different source types.",
                      "Use one supported type in every platform branch", at: argument)
                return nil
            }
            type = type ?? value.type
            values.append(value.expression)
        }
        return TypedExpression(Expression(.platformValue(PlatformAlternatives(
            ios: values[0], android: values[1], harmonyOS: values[2])), location: location(of: call)), type)
    }

    private struct TypedExpression {
        let expression: Expression
        let type: ValueType?
        init(_ expression: Expression, _ type: ValueType?) {
            self.expression = expression
            self.type = type
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
