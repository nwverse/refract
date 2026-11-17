import RefractIR
import RefractMapping
import SwiftParser
import SwiftSyntax

public struct Frontend {
    public init() {}

    public static func parse(_ source: SourceFile, mapping: Mapping? = nil) -> TranslationUnit {
        let tree = Parser.parse(source: source.contents)
        let parserDiagnostics = ParserDiagnostics.validate(tree: tree, file: source.path)
        guard parserDiagnostics.isEmpty else {
            return TranslationUnit(module: Module(sourceFile: source.path, screens: []),
                                   diagnostics: parserDiagnostics)
        }
        let builder = Builder(file: source.path, tree: tree, mapping: mapping)
        builder.walk(tree)
        let module = Module(sourceFile: source.path, screens: builder.screens,
                            nativeDeclarations: builder.interop.declarations,
                            models: builder.models, itemTypes: builder.itemTypes,
                            enums: builder.enums)
        builder.validateChildViewGraph(module)
        builder.validateRowContentTypes(module)
        return TranslationUnit(module: module,
                               diagnostics: builder.diagnostics)
    }
}

final class Builder: SyntaxVisitor {
    let file: String
    let converter: SourceLocationConverter
    var screens: [Screen] = []
    var diagnostics: [Diagnostic] = []
    var interop: InteropFrontend
    var designSystem: DesignSystemFrontend?
    var parameters: [ScreenParameter] = []
    var currentViewName: String?
    var declaredModelNames: Set<String> = []
    var currentStates: [StateDeclaration] = []
    var models: [ModelProtocol] = []
    var itemTypes: [ItemType] = []
    var enums: [EnumDeclaration] = []
    var currentModels: [ModelReference] = []
    var currentListItem: String?
    var currentListItemType: ItemType?
    var currentBindings: [String: ValueType] = [:]
    var viewDeclarations: [String: StructDeclSyntax] = [:]

    init(file: String, tree: SourceFileSyntax, mapping: Mapping?) {
        self.file = file
        self.converter = SourceLocationConverter(fileName: file, tree: tree)
        self.interop = InteropFrontend(file: file, converter: converter)
        self.designSystem = nil
        super.init(viewMode: .sourceAccurate)
        if let mapping { self.designSystem = DesignSystemFrontend(builder: self, mapping: mapping) }
        declaredModelNames = Set(tree.statements.compactMap { statement in
            guard let declaration = statement.item.as(ProtocolDeclSyntax.self),
                  declaration.inheritanceClause?.inheritedTypes.contains(where: {
                      $0.type.trimmedDescription == "RefractModel"
                  }) == true else { return nil }
            return declaration.name.text
        })
        collectEnums(tree)
        collectItemTypes(tree)
        collectModels(tree)
        for statement in tree.statements {
            if let declaration = statement.item.as(StructDeclSyntax.self),
               declaration.inheritanceClause?.inheritedTypes.contains(where: {
                   $0.type.trimmedDescription == "View"
               }) == true {
                viewDeclarations[declaration.name.text] = declaration
            }
        }
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if interop.declaration(node) {
            diagnostics.append(contentsOf: interop.takeDiagnostics())
            return .skipChildren
        }
        guard node.inheritanceClause?.inheritedTypes.contains(where: {
            $0.type.trimmedDescription == "View"
        }) == true else { return .skipChildren }
        guard validateViewMembers(node) else { return .skipChildren }

        let savedParameters = parameters
        let savedStates = currentStates
        let savedModels = currentModels
        let savedItem = currentListItem
        let savedItemType = currentListItemType
        let savedBindings = currentBindings
        let savedViewName = currentViewName
        parameters = []
        currentStates = []
        currentModels = []
        currentListItem = nil
        currentListItemType = nil
        currentBindings = [:]
        currentViewName = node.name.text
        defer {
            parameters = savedParameters
            currentStates = savedStates
            currentModels = savedModels
            currentListItem = savedItem
            currentListItemType = savedItemType
            currentBindings = savedBindings
            currentViewName = savedViewName
        }
        let members = node.memberBlock.members
        let hasItemInputs = members.contains { member in
            guard let type = member.decl.as(VariableDeclSyntax.self)?.bindings.first?.typeAnnotation?.type
                .trimmedDescription else { return false }
            return itemTypes.contains(where: { $0.name == type })
        }
        if hasItemInputs {
            guard let body = typedInputScreen(node, members: members) else { return .skipChildren }
            screens.append(body)
            return .skipChildren
        }
        if hasDeclaredModelInputs(node) && !hasTypedInputs(members) {
            guard localStateDeclarations(node) != nil else { return .skipChildren }
        } else if hasTypedInputs(members) {
            guard let body = typedInputScreen(node, members: members) else { return .skipChildren }
            screens.append(body)
            return .skipChildren
        }
        guard let body = node.memberBlock.members.first(where: {
            $0.decl.as(VariableDeclSyntax.self)?.bindings.first?.pattern
                .as(IdentifierPatternSyntax.self)?.identifier.text == "body"
        })?.decl.as(VariableDeclSyntax.self),
            body.bindings.count == 1,
            let binding = body.bindings.first,
            binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "body",
            let accessors = binding.accessorBlock?.accessors,
            case let .getter(items) = accessors else {
            error("unsupportedViewBody", "A View must have one expression-bodied `body` getter and no stored properties yet.",
                  "Return a supported view from `body`.", at: node.name)
            return .skipChildren
        }
        if items.contains(where: { $0.item.as(IfConfigDeclSyntax.self) != nil }) {
            return .visitChildren
        }
        guard let states = localStateDeclarations(node) else { return .skipChildren }
        currentStates = states
        currentModels = states.compactMap {
            guard case let .model(reference, _) = $0 else { return nil }
            return reference
        }
        parameters = []
        currentListItem = nil
        currentListItemType = nil
        defer {
            currentStates = []
            currentModels = []
            currentListItem = nil
            currentListItemType = nil
        }
        guard let root = viewStatements(items, body: binding) else { return .skipChildren }

        screens.append(Screen(name: node.name.text, parameters: parameters, states: states,
                              body: root, location: location(of: node.name)))
        return .skipChildren
    }

    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        error("RFVIEW005", "Free-form conditional compilation hides platform-specific Swift code from the generator.",
              "Use `refractValue`, `refractView`, or a declared `RefractNativeView`", at: node.clauses)
        return .skipChildren
    }

    func view(_ expression: ExprSyntax) -> ViewNode? {
        if let call = expression.as(FunctionCallExprSyntax.self), forEachCall(expression) != nil {
            error("RFLIST003", "ForEach must be the sole dynamic child directly owned by List, not nested or eagerly rendered.",
                  "Use List { ForEach(model.items) { item in ... } } with a stable stored id", at: call)
            return nil
        }
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
            if extendedViewHandles(name: call.calledExpression.trimmedDescription) {
                return extendedView(call)
            }
            if let control = stateControl(call) { return control }
            return view(call)
        }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base {            guard let node = view(base) else { return nil }
            return modifier(member, on: node)
        }
        error("unsupportedExpression", "The expression `\(expression.trimmedDescription)` is not a supported view.",
              "Use VStack, HStack, Text, or Button.", at: expression)
        return nil
    }

    func modifier(_ call: FunctionCallExprSyntax, name: String, on node: ViewNode) -> ViewNode? {
        if name == "refractNativeModifier" { return nativeModifier(call, on: node) }
        if name == "labelsHidden" { return labelsHidden(call, on: node) }
        if name == "accessibilityLabel" { return accessibilityLabel(call, on: node) }
        let before = diagnostics.count
        if let builtin = builtinModifier(call, name: name) {
            if diagnostics.count > before { return nil }
            if !builtin.arguments.isEmpty || call.arguments.isEmpty {
                guard let updated = node.appendingModifier(builtin) else {
                    error("unsupportedModifierTarget", "This modifier target is not supported yet.",
                          "Apply the modifier to a supported built-in view.", at: call)
                    return nil
                }
                return updated
            }
        }
        if diagnostics.count > before { return nil }
        guard name == "padding" || name == "background" || designSystem != nil, call.arguments.count <= 1, call.trailingClosure == nil else {
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

    func modifier(_ name: String, arguments: [Expression], on node: ViewNode,
                          at syntax: some SyntaxProtocol) -> ViewNode? {
        if case let .component(component, _) = node {
            return designSystem?.modifiers([Modifier(name: name, arguments: arguments, location: location(of: syntax))], on: component)
        }
        let modifier = Modifier(name: name, arguments: arguments, location: location(of: syntax))
        if let updated = node.appendingModifier(modifier) { return updated }
        error("unsupportedModifierTarget", "This modifier target is not supported yet.", at: syntax)
        return nil
    }

    func view(_ call: FunctionCallExprSyntax) -> ViewNode? {
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
            guard call.arguments.isEmpty, call.trailingClosure != nil,
                  let children = children(of: call.trailingClosure) else {
                error("unsupportedViewArguments", "\(name) supports only an unlabeled child closure.", at: call)
                return nil
            }
            return .stack(axis: name == "VStack" ? .vertical : .horizontal,
                          children: children, modifiers: [], location: nodeLocation)
        case "Text":
            let beforeText = diagnostics.count
            if let argument = call.arguments.first, argument.label == nil,
               let value = modelTypedProperty(argument.expression) {
                guard value.type == .string else {
                    error("RFSEM001", "Text requires a String expression, not the declared scalar type of this property.",
                          "Use a String item or model property, or a supported localized interpolation", at: argument.expression)
                    return nil
                }
                return .text(value.expression, modifiers: [], location: nodeLocation)
            }
            if let argument = call.arguments.first, argument.label == nil,
               let reference = argument.expression.as(DeclReferenceExprSyntax.self),
               parameters.contains(where: { $0.name == reference.baseName.text && $0.isOptional }) {
                error("RFSEM002", "Optional input `\(reference.baseName.text)` requires an explicit if let binding before scalar use.",
                      "Use `if let value = \(reference.baseName.text) { ... } else { ... }` in the view builder",
                      at: argument.expression)
                return nil
            }
            var parser = LocalizationFrontend(file: file, converter: converter, scalar: scalar,
                                              typedScalar: modelTypedProperty,
                                              stateText: currentStates.isEmpty ? { _ in nil } : stateText,
                                              enumInputNames: Set(parameters.compactMap { $0.enumName == nil ? nil : $0.name }))
            guard let value = parser.text(call, arguments: call.arguments) else {
                diagnostics.append(contentsOf: parser.diagnostics)
                return nil
            }
            diagnostics.append(contentsOf: parser.diagnostics)
            guard diagnostics.count == beforeText else { return nil }
            return .text(value, modifiers: [], location: nodeLocation)
        case "Button":
            if call.arguments.isEmpty, call.additionalTrailingClosures.count == 1,
               call.additionalTrailingClosures.first?.label.text == "label",
               let labelClosure = call.additionalTrailingClosures.first?.closure,
               let action = localStateAction(call.trailingClosure) {
                let children = children(of: labelClosure)
                guard children?.count == 1, let child = children?.first else {
                    error("unsupportedButton", "A custom Button label must contain one Label view.",
                          "Use Button { model.save() } label: { Label(...) }", at: labelClosure)
                    return nil
                }
                return .button(label: child, action: action, modifiers: [], location: nodeLocation)
            }
            guard call.arguments.count == 1,
                  let argument = call.arguments.first,
                  argument.label == nil || argument.label?.text == "verbatim",
                  call.additionalTrailingClosures.isEmpty else {
                error("unsupportedButton", "Button requires one localized string title and an empty action.",
                      "Use Button(\"key\") { } or a literal text label with explicit provenance", at: call)
                return nil
            }
            let action = localStateAction(call.trailingClosure)
            guard action != nil || call.trailingClosure?.statements.isEmpty != false else { return nil }
            var parser = LocalizationFrontend(file: file, converter: converter, scalar: scalar,
                                              typedScalar: modelTypedProperty,
                                              stateText: currentStates.isEmpty ? { _ in nil } : stateText,
                                              enumInputNames: Set(parameters.compactMap { $0.enumName == nil ? nil : $0.name }))
            guard let labelText = parser.text(call, arguments: call.arguments,
                                              allowsTrailingClosure: true) else {
                diagnostics.append(contentsOf: parser.diagnostics)
                return nil
            }
            diagnostics.append(contentsOf: parser.diagnostics)
            let label = ViewNode.text(labelText, modifiers: [], location: nodeLocation)
            return .button(label: label, action: action, modifiers: [], location: nodeLocation)
        case "refractView":
            return platformView(call)
        default:
            if let declaration = viewDeclarations[name] {
                return childView(call, declaration: declaration)
            }
            if interop.declarations.contains(where: { $0.name == name }) == false,
               designSystem?.isCandidate(name) == true {
                return designSystem?.component(call, name: name)
            }
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

    func scalar(_ expression: ExprSyntax) -> TypedExpression? {
        if let string = stringLiteral(expression) {
            return TypedExpression(Expression(.stringLiteral(string), type: .string,
                                             location: location(of: expression)), .string)
        }
        if let literal = expression.as(BooleanLiteralExprSyntax.self) {
            return TypedExpression(Expression(.boolLiteral(literal.literal.tokenKind == .keyword(.true)),
                                             type: .bool, location: location(of: expression)), .bool)
        }
        if let literal = expression.as(IntegerLiteralExprSyntax.self) {
            return TypedExpression(Expression(.numberLiteral(literal.literal.text), type: .int,
                                             location: location(of: expression)), .int)
        }
        if let literal = expression.as(FloatLiteralExprSyntax.self) {
            return TypedExpression(Expression(.numberLiteral(literal.literal.text), type: .double,
                                             location: location(of: expression)), .double)
        }
        if expression.as(MemberAccessExprSyntax.self) != nil {
            return TypedExpression(Expression(.reference(expression.trimmedDescription),
                                             location: location(of: expression)), nil)
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            if let binding = currentBindings[name] {
                return TypedExpression(Expression(.reference(name), type: binding,
                                                 location: location(of: expression)), binding)
            }
            for declaration in currentStates {
                switch declaration {
                case let .state(declared, type, _, _) where declared == name:
                    return TypedExpression(Expression(.valueProperty(.state(name)), type: type,
                                                     location: location(of: expression)), type)
                case let .binding(declared, type, _) where declared == name:
                    return TypedExpression(Expression(.valueProperty(.binding(name)), type: type,
                                                     location: location(of: expression)), type)
                default: continue
                }
            }
            if let model = modelTypedProperty(expression) { return model }
            // An enum is a finite control-flow subject, not a scalar text or formatting value.
            guard !parameters.contains(where: { $0.name == reference.baseName.text && $0.enumName != nil }) else {
                error("RFSEM002", "An enum input cannot be used as a scalar expression.",
                      "Switch explicitly over the enum, or expose a separate scalar model property", at: expression)
                return nil
            }
            if parameters.contains(where: { $0.name == name && $0.enumName == nil && $0.isOptional }) {
                error("RFSEM002", "Optional input `\(name)` requires an explicit if let binding before scalar use.",
                      "Use `if let value = \(name) { ... } else { ... }` in the view builder", at: expression)
                return nil
            }
            // A bare screen input carries its declared type; nested model members are refined by the state frontend.
            let type = parameters.first { $0.name == name }?.type
            return TypedExpression(Expression(.reference(name), type: type,
                                             location: location(of: expression)), type)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "refractValue" {
            return platformValue(call)
        }
        error("RFSEM001", "The expression `\(expression.trimmedDescription)` is not a supported scalar value.",
              "Use a supported literal, typed property, or `refractValue`", at: expression)
        return nil
    }

    func platformValue(_ call: FunctionCallExprSyntax) -> TypedExpression? {
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

    func children(of closure: ClosureExprSyntax?) -> [ViewNode]? {
        guard let closure else { return [] }
        var result: [ViewNode] = []
        for item in closure.statements {
            guard let child = viewStatement(item) else { return nil }
            result.append(child)
        }
        return result
    }

    func viewStatement(_ item: CodeBlockItemSyntax) -> ViewNode? {
        if let statement = item.item.as(ExpressionStmtSyntax.self) {
            if let conditional = statement.expression.as(IfExprSyntax.self) { return view(conditional) }
            if let switchStatement = statement.expression.as(SwitchExprSyntax.self) {
                return view(switchStatement)
            }
        }
        guard let expression = item.item.as(ExprSyntax.self) else {
            if item.item.is(SwitchExprSyntax.self) {
                error("RFCTRL003", "Switch requires a declared enum-typed immutable screen input.",
                      "Use `let value: YourEnum` with a local no-payload enum declaration", at: item)
            } else {
                error("unsupportedStatement", "Only view expressions and typed conditionals are allowed in a view builder.",
                      "Remove local statements or move them behind a model", at: item)
            }
            return nil
        }
        if let switchStatement = expression.as(SwitchExprSyntax.self) {
            return view(switchStatement)
        }
        return view(expression)
    }

    func viewStatements(_ items: CodeBlockItemListSyntax, body: PatternBindingSyntax) -> ViewNode? {
        if items.count != 1, items.first != nil {
            diagnostics.append(Diagnostic(code: "unsupportedViewBody",
                message: "The `body` getter must return exactly one view expression.",
                suggestion: "Return a supported view from `body`.", location: location(of: body.pattern)))
            return nil
        }
        guard expression(in: items) != nil else {
            guard items.count == 1, let first = items.first else {
                error("unsupportedViewBody", "The `body` getter must return exactly one view expression.",
                      "Return a supported view from `body`.", at: items)
                return nil
            }
            if let conditional = first.item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self) {
                return view(conditional)
            }
            if let switchStatement = first.item.as(ExpressionStmtSyntax.self)?.expression.as(SwitchExprSyntax.self) {
                return view(switchStatement)
            }
            if first.item.is(SwitchExprSyntax.self) {
                error("RFCTRL003", "Switch requires a declared enum-typed immutable screen input.",
                      "Use `let value: YourEnum` with a local no-payload enum declaration", at: first)
                return nil
            }
            error("unsupportedViewBody", "The `body` getter must return exactly one view expression.",
                  "Return a supported view from `body`.", at: body.pattern)
            return nil
        }
        return viewStatement(items.first!)
    }

    func expression(in items: CodeBlockItemListSyntax) -> ExprSyntax? {
        guard items.count == 1, let item = items.first else { return nil }
        if let expression = item.item.as(ExprSyntax.self) { return expression }
        return item.item.as(ReturnStmtSyntax.self)?.expression
    }

    func stringLiteral(_ expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self), literal.segments.count == 1,
            case let .stringSegment(segment)? = literal.segments.first else { return nil }
        return segment.content.text
    }

    func location(of node: some SyntaxProtocol) -> RefractIR.SourceLocation {
        let position = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        return RefractIR.SourceLocation(file: file, line: position.line, column: position.column)
    }

    func error(_ code: String, _ message: String, _ suggestion: String? = nil,
                       at node: some SyntaxProtocol) {
        diagnostics.append(Diagnostic(code: code, message: message, suggestion: suggestion,
                                      location: location(of: node)))
    }
}
