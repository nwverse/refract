import RefractIR
import SwiftParser
import SwiftSyntax

/// Shared scalar typing for native arguments and localization interpolation.
extension Builder {
    func hasTypedInputs(_ members: MemberBlockItemListSyntax) -> Bool {
        members.contains { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.attributes.isEmpty,
                  variable.bindingSpecifier.tokenKind == .keyword(.let),
                  let binding = variable.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else { return false }
            if let type = binding.typeAnnotation?.type.trimmedDescription,
               models.contains(where: { $0.name == type }) || nativeHosts.contains(where: { $0.name == type }) {
                return false
            }
            return identifier.text != "body"
        }
    }

    func hasDeclaredModelInputs(_ node: StructDeclSyntax) -> Bool {
        node.memberBlock.members.contains { member in
            guard let type = member.decl.as(VariableDeclSyntax.self)?.bindings.first?.typeAnnotation?.type
                .trimmedDescription else { return false }
            return declaredModelNames.contains(type)
        }
    }

    func typedInputScreen(_ node: StructDeclSyntax,
                          members: MemberBlockItemListSyntax) -> Screen? {
        if node.name.text == "MessageBlock", itemTypes.contains(where: { $0.name == "ChatBlock" }) {
            return messageBlockInputScreen(node, members: members)
        }
        var parameters: [ScreenParameter] = []
        let savedParameters = self.parameters
        defer { self.parameters = savedParameters }
        let hasItemInput = members.contains { member in
            guard let type = member.decl.as(VariableDeclSyntax.self)?.bindings.first?.typeAnnotation?.type
                .trimmedDescription else { return false }
            return itemTypes.contains(where: { $0.name == type })
        }
        guard let states = hasItemInput ? localInputStates(node) : localStateDeclarations(node) else { return nil }
        if states.contains(where: {
            guard case .state = $0 else { return false }
            return true
        }) {
            error("state.invalid_declaration", "A typed-input child View cannot mix local state with model/item inputs.",
                  "Keep local state in the parent or use a dedicated state-only View.", at: node.name)
            return nil
        }
        currentModels = states.compactMap {
            guard case let .model(reference, _) = $0 else { return nil }
            return reference
        }
        currentHosts = states.compactMap {
            guard case let .nativeHost(reference, _) = $0 else { return nil }
            return reference
        }
        currentStates = states
        guard let native = nativeScreenInputs(node, states: states) else { return nil }
        currentNativeValues = native.values
        let savedItem = currentListItem
        let savedItemType = currentListItemType
        defer {
            currentModels = []
            currentStates = []
            currentListItem = savedItem
            currentListItemType = savedItemType
        }
        var itemInput: (name: String, type: ItemType)?
        var body: VariableDeclSyntax?
        for member in members {
            let inputType = member.decl.as(VariableDeclSyntax.self)?.bindings.first?.typeAnnotation?.type
                .trimmedDescription ?? ""
            let isItemInput = itemTypes.contains(where: { $0.name == inputType })
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.modifiers.isEmpty,
                  variable.bindings.count == 1, let binding = variable.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
                  identifier.text == "body" || isItemInput || !hasItemInput ||
                    (models.contains(where: { $0.name == binding.typeAnnotation?.type.trimmedDescription ?? "" })) else {
                error("RFVIEW006", "This child View accepts only declared model and Identifiable item stored inputs.",
                      "Remove other stored inputs or move them into the declared model contract.", at: member)
                return nil
            }
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.modifiers.isEmpty,
                  variable.bindings.count == 1, let binding = variable.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
                error("R.string.interpolation", "Only typed immutable inputs and body belong in a View.",
                      "Move other declarations behind a model or native component", at: member)
                return nil
            }
            if identifier.text == "body" {
                body = variable
                continue
            }
            if let type = binding.typeAnnotation?.type.trimmedDescription,
               models.contains(where: { $0.name == type }) || nativeHosts.contains(where: { $0.name == type }) ||
                NativeValueKind.allCases.contains(where: { $0.typeName == type }) {
                continue
            }
            guard variable.bindingSpecifier.tokenKind == .keyword(.let), binding.initializer == nil,
                  binding.accessorBlock == nil, let type = binding.typeAnnotation?.type else {
                error("RFSEM001", "View inputs must be immutable properties with an explicit supported type.",
                      "Use a scalar, optional scalar or supported local enum input", at: member)
                return nil
            }
            if let optional = type.as(OptionalTypeSyntax.self) {
                guard let valueType = ValueType(frontendName: optional.wrappedType.trimmedDescription) else {
                    error("RFCTRL002", "Only optional scalar screen inputs can be bound in view conditionals.",
                          "Use `let name: String?`, `Int?`, `Double?` or `Bool?` with if let", at: type)
                    return nil
                }
                parameters.append(ScreenParameter(name: identifier.text, type: valueType, isOptional: true,
                                                  location: location(of: identifier)))
                continue
            }
            if let declaration = enums.first(where: { $0.name == type.trimmedDescription }) {
                parameters.append(ScreenParameter(name: identifier.text, type: .string, enumName: declaration.name,
                                                  location: location(of: identifier)))
                continue
            }
            if diagnostics.contains(where: { $0.code == "RFCTRL006" }) { return nil }
            if let type = binding.typeAnnotation?.type.trimmedDescription,
               let item = itemTypes.first(where: { $0.name == type }) {
                guard itemInput == nil else {
                    error("RFVIEW006", "This child View slice accepts one Identifiable item input.",
                          "Keep one typed current item and any declared model owners.", at: member)
                    return nil
                }
                itemInput = (identifier.text, item)
                parameters.append(ScreenParameter(name: identifier.text, type: item.identity.type, itemType: item.name,
                                                  location: location(of: identifier)))
                continue
            }
            if type.trimmedDescription == "RemoteImageLoader",
               interop.declarations.contains(where: {
                   $0.parameters.contains { $0.type == .remoteImageLoader }
               }) {
                parameters.append(ScreenParameter(name: identifier.text, type: .string, itemType: "RemoteImageLoader",
                                                  location: location(of: identifier)))
                continue
            }
            guard let valueType = ValueType(frontendName: type.trimmedDescription) else {
                error("RFSEM001", "View inputs must use a supported scalar, optional scalar or declared enum type.",
                      "Declare a supported immutable input type explicitly", at: member)
                return nil
            }
            parameters.append(ScreenParameter(name: identifier.text, type: valueType,
                                              location: location(of: identifier)))
        }
        guard let body, let binding = body.bindings.first,
              let accessors = binding.accessorBlock?.accessors,
              case let .getter(items) = accessors else {
            error("unsupportedViewBody", "A View with scalar inputs must have one expression-bodied body.",
                  "Return a supported view from `body`", at: node.name)
            return nil
        }
        if items.contains(where: { $0.item.as(IfConfigDeclSyntax.self) != nil }) {
            error("RFVIEW005", "Free-form conditional compilation hides platform-specific Swift code from the generator.",
                  "Use `refractValue`, `refractView`, or a declared `RefractNativeView`", at: body)
            return nil
        }
        self.parameters = parameters
        currentBindings = [:]
        if let itemInput {
            currentListItem = itemInput.name
            currentListItemType = itemInput.type
        }
        guard let root = viewStatements(items, body: binding) else { return nil }
        return Screen(name: node.name.text, parameters: parameters, states: states, body: root,
                      nativeValues: native.values, lifecycle: native.lifecycle, location: location(of: node.name))
    }
}

struct TypedExpression {
    let expression: Expression
    let type: ValueType?

    init(_ expression: Expression, _ type: ValueType?) {
        self.expression = expression
        self.type = type
    }
}

/// User-facing-string provenance is established here; backends never guess it from a string literal.
struct LocalizationFrontend {
    let file: String
    let converter: SourceLocationConverter
    let scalar: (ExprSyntax) -> TypedExpression?
    let typedScalar: ((ExprSyntax) -> TypedExpression?)?
    let stateText: (ExprSyntax) -> Expression?
    let enumInputNames: Set<String>
    let nativeValues: [NativeValueReference]

    init(file: String, converter: SourceLocationConverter,
         scalar: @escaping (ExprSyntax) -> TypedExpression?,
         typedScalar: ((ExprSyntax) -> TypedExpression?)? = nil,
         stateText: @escaping (ExprSyntax) -> Expression?,
         enumInputNames: Set<String> = [], nativeValues: [NativeValueReference] = []) {
        self.file = file
        self.converter = converter
        self.scalar = scalar
        self.typedScalar = typedScalar
        self.stateText = stateText
        self.enumInputNames = enumInputNames
        self.nativeValues = nativeValues
    }
    private(set) var diagnostics: [Diagnostic] = []

    mutating func text(_ call: FunctionCallExprSyntax, arguments: LabeledExprListSyntax,
                       allowsTrailingClosure: Bool = false) -> Expression? {
        guard let result = tryParse(call, arguments: arguments,
                                    allowsTrailingClosure: allowsTrailingClosure) else { return nil }
        return Expression(result.value, type: result.type, location: location(of: call))
    }

    private mutating func tryParse(_ call: FunctionCallExprSyntax,
                                   arguments: LabeledExprListSyntax,
                                   allowsTrailingClosure: Bool) -> Expression? {
        guard arguments.count == 1, let argument = arguments.first,
              allowsTrailingClosure || call.trailingClosure == nil else {
            error("R.string.unsupported_expression", "Text requires one localized key or an explicitly verbatim string.",
                  "Use Text(\"key\") or Text(verbatim: \"literal\")", at: call)
            return nil
        }
        if argument.label?.text == "verbatim" {
            if let native = nativeValue(argument.expression), native.type == .string {
                return native.expression
            }
            if let value = stateText(argument.expression) {
                return value
            }
            if let call = argument.expression.as(FunctionCallExprSyntax.self),
               call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "refractValue" {
                return verbatimPlatformText(call)
            }
            guard let literal = argument.expression.as(StringLiteralExprSyntax.self),
                  let value = literal.representedLiteralValue else {
                error("R.string.literal", "Verbatim text must be a literal without interpolation or a typed `refractValue(ios:android:harmonyOS:)` of literals.",
                      "Use Text(verbatim: \"literal\") or Text(verbatim: refractValue(ios: \"iOS\", android: \"Android\", harmonyOS: \"HarmonyOS\")) for intentional non-localized text", at: argument.expression)
                return nil
            }
            return Expression(.verbatimText(value), type: .string, location: location(of: argument.expression))
        }
        guard argument.label == nil else {
            error("R.string.unsupported_expression", "This Text argument label is not in the localization subset.",
                  "Use Text(\"key\") or Text(verbatim: \"literal\")", at: argument)
            return nil
        }
        return localized(argument.expression)
    }

    mutating func localized(_ expression: ExprSyntax) -> Expression? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "refractValue" {
            error("R.string.unsupported_expression",
                  "Platform-selected text passed to Text(_:) would be treated as a localization key on iOS, diverging from the verbatim native output.",
                  "Use Text(verbatim: refractValue(ios: \"...\", android: \"...\", harmonyOS: \"...\")) for per-platform literal text, or Text(\"key\") with a canonical localization key.", at: call)
            return nil
        }
        if let literal = expression.as(StringLiteralExprSyntax.self) {
            if literal.segments.contains(where: {
                guard case .expressionSegment = $0 else { return false }
                return true
            }) {
                if nativeStringInterpolation(literal) { return localizedLiteral(literal) }
                if let typedScalar, literal.segments.contains(where: {
                    guard case let .expressionSegment(segment) = $0 else { return false }
                    return segment.expressions.contains { typedScalar($0.expression) != nil }
                }) {
                    return localizedLiteral(literal)
                }
                if let value = stateText(expression), case .interpolatedString = value.value {
                    return value
                }
                return localizedLiteral(literal)
            }
            if let value = stateText(expression), case .interpolatedString = value.value {
                return value
            }
            return localizedLiteral(literal)
        }
        if let call = expression.as(FunctionCallExprSyntax.self) {
            guard let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text else {
                error("R.string.invalid_key", "A localized key must be constructed from a static literal.",
                      "Use Text(LocalizedStringKey(\"key\")) or String(localized: \"key\")", at: expression)
                return nil
            }
            switch name {
            case "LocalizedStringKey":
                guard call.arguments.count == 1, call.arguments.first?.label == nil,
                      let literal = call.arguments.first?.expression.as(StringLiteralExprSyntax.self) else {
                    error("R.string.invalid_key", "LocalizedStringKey requires one static string literal.",
                          "Use Text(LocalizedStringKey(\"key\"))", at: call)
                    return nil
                }
                return localizedLiteral(literal)
            case "String":
                guard call.arguments.map(\.label?.text) == ["localized"],
                      let literal = call.arguments.first?.expression.as(StringLiteralExprSyntax.self),
                      literal.representedLiteralValue != nil else {
                    error("R.string.unsupported_expression", "String(localized:) requires one literal key in this subset.",
                          "Use String(localized: \"key\"), typed interpolation, or Text(verbatim:) for intentional non-localized text", at: call)
                    return nil
                }
                return localizedLiteral(literal)
            default:
                break
            }
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "refractValue" {
            // The early `localized(_:)` branch above already emitted the verbatim/localized
            // diagnostic for `Text(refractValue(...))`. Reaching this branch from a nested
            // helper (for example `String(localized: refractValue(...))`) is unsupported too.
            error("R.string.unsupported_expression",
                  "Platform-selected text is not a static localization key.",
                  "Use Text(verbatim: refractValue(ios: \"...\", android: \"...\", harmonyOS: \"...\")) for per-platform literal text, or String(localized: \"key\") with a canonical key.", at: call)
            return nil
        }
        guard let value = scalar(expression), value.type == .string else {
            if diagnostics.last?.code == "RFSEM002" { return nil }
            if diagnostics.isEmpty {
                error("R.string.invalid_key", "This expression does not provide a static localization key.",
                      "Use a static key or Text(verbatim:) for intentional literal text", at: expression)
            }
            return nil
        }
        return value.expression
    }

    private mutating func verbatimPlatformText(_ call: FunctionCallExprSyntax) -> Expression? {
        guard call.arguments.map(\.label?.text) == ["ios", "android", "harmonyOS"] else {
            error("RFNATIVE003", "`refractValue` requires exactly `ios`, `android`, and `harmonyOS` arguments with compatible types.",
                  "Supply all three typed platform values", at: call)
            return nil
        }
        var values: [Expression] = []
        for argument in call.arguments {
            guard let literal = argument.expression.as(StringLiteralExprSyntax.self),
                  let text = literal.representedLiteralValue else {
                error("RFNATIVE003", "Platform verbatim text alternatives must all be string literals without interpolation.",
                      "Use a nonlocalized literal string in every platform branch of Text(verbatim: refractValue(...))", at: argument)
                return nil
            }
            values.append(Expression(.verbatimText(text), type: .string, location: location(of: argument.expression)))
        }
        return Expression(.platformValue(PlatformAlternatives(
            ios: values[0], android: values[1], harmonyOS: values[2])), type: .string,
            location: location(of: call))
    }

    private func nativeValue(_ expression: ExprSyntax) -> TypedExpression? {
        guard let member = expression.as(MemberAccessExprSyntax.self),
              let base = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let field = NativeValueField(rawValue: member.declName.baseName.text),
              let value = nativeValues.first(where: { $0.propertyName == base }),
              value.selectedField == field || value.selectedField == .id && field == .revision else { return nil }
        return TypedExpression(Expression(.nativeValueProperty(NativeValueProperty(value: base, field: field)),
                                        type: field.type, location: location(of: expression)), field.type)
    }

    private func nativeStringInterpolation(_ literal: StringLiteralExprSyntax) -> Bool {
        literal.segments.contains { segment in
            guard case let .expressionSegment(segment) = segment else { return false }
            return segment.expressions.contains {
                guard let member = $0.expression.as(MemberAccessExprSyntax.self),
                      let base = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
                      let field = NativeValueField(rawValue: member.declName.baseName.text) else { return false }
                return nativeValues.contains(where: { value in
                    value.propertyName == base && (value.selectedField == field || value.selectedField == .id && field == .revision)
                })
            }
        }
    }

    private mutating func localizedLiteral(_ literal: StringLiteralExprSyntax) -> Expression? {
        var key = ""
        var arguments: [Expression] = []
        for segment in literal.segments {
            switch segment {
            case let .stringSegment(segment):
                // An escape cannot hide an argument or transform the resource key unexpectedly.
                guard !segment.content.text.contains("\\") else {
                    error("R.string.invalid_key", "Localization keys cannot contain escape sequences.",
                          "Use plain lowercase ASCII dot-separated key segments", at: segment)
                    return nil
                }
                key += segment.content.text
            case let .expressionSegment(segment):
                let expressions = segment.expressions.map(\.expression)
                guard expressions.count == 1, let expression = expressions.first else {
                    error("R.string.interpolation", "Localized interpolation must contain one typed scalar expression.",
                          "Use a declared String, Int or Double input without custom formatting", at: segment)
                    return nil
                }
                if let reference = expression.as(DeclReferenceExprSyntax.self),
                   enumInputNames.contains(reference.baseName.text) {
                    diagnostics.append(Diagnostic(code: "RFSEM002",
                        message: "An enum input cannot be used as a scalar expression.",
                        suggestion: "Switch explicitly over the enum, or expose a separate scalar model property",
                        location: location(of: expression)))
                    return nil
                }
                if let typedValue = typedScalar?(expression) {
                    guard let type = typedValue.type, type != .bool else {
                        error("R.string.interpolation", "Localized interpolation requires a statically known String, Int or Double.",
                              "Declare the interpolated model property as String, Int or Double", at: expression)
                        return nil
                    }
                    arguments.append(Expression(typedValue.expression.value, type: type,
                                                location: typedValue.expression.location))
                    continue
                }
                guard let value = scalar(expression) else {
                    if expression.as(MemberAccessExprSyntax.self) != nil {
                        error("R.string.interpolation", "Interpolation must resolve to a typed scalar screen or native input field.",
                              "Use a supported scalar input, not an opaque expression", at: expression)
                    }
                    return nil
                }
                guard let type = value.type, type != .bool else {
                    error("R.string.interpolation", "Localized interpolation requires a statically known String, Int or Double.",
                          "Declare the interpolated screen input with an explicit supported type", at: expression)
                    return nil
                }
                arguments.append(Expression(value.expression.value, type: type,
                                            location: value.expression.location))
            }
        }
        guard LocalizationKey.isCanonical(key) else {
            error("R.string.invalid_key", "String key `\(key)` is not a lowercase dot-separated resource key.",
                  "Use lowercase ASCII letter-led segments with only lowercase ASCII letters and digits; display punctuation and whitespace belong in the resource value", at: literal)
            return nil
        }
        let result = LocalizedText(key: key, arguments: arguments)
        return Expression(.localizedText(result), type: .string, location: location(of: literal))
    }

    private func location(of node: some SyntaxProtocol) -> RefractIR.SourceLocation {
        let position = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        return RefractIR.SourceLocation(file: file, line: position.line, column: position.column)
    }

    private mutating func error(_ code: String, _ message: String, _ suggestion: String? = nil,
                                at node: some SyntaxProtocol) {
        diagnostics.append(Diagnostic(code: code, message: message, suggestion: suggestion,
                                      location: location(of: node)))
    }
}
