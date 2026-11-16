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
            return identifier.text != "body"
        }
    }

    func typedInputScreen(_ node: StructDeclSyntax,
                          members: MemberBlockItemListSyntax) -> Screen? {
        var body: VariableDeclSyntax?
        for member in members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.attributes.isEmpty, variable.modifiers.isEmpty,
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
            guard variable.bindingSpecifier.tokenKind == .keyword(.let), binding.initializer == nil,
                  binding.accessorBlock == nil, let type = binding.typeAnnotation?.type,
                  let valueType = ValueType(frontendName: type.trimmedDescription) else {
                error("R.string.interpolation", "Formatted text inputs must be immutable String, Int or Double properties.",
                      "Declare inputs as `let name: String`, `let count: Int` or `let ratio: Double`", at: member)
                return nil
            }
            parameters.append(ScreenParameter(name: identifier.text, type: valueType,
                                              location: location(of: identifier)))
        }
        guard let body, let binding = body.bindings.first,
              let accessors = binding.accessorBlock?.accessors,
              case let .getter(items) = accessors,
              let expression = expression(in: items), let root = view(expression) else {
            error("unsupportedViewBody", "A View with scalar inputs must have one expression-bodied body.",
                  "Return a supported view from `body`", at: node.name)
            return nil
        }
        return Screen(name: node.name.text, parameters: parameters, body: root,
                      location: location(of: node.name))
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
    let stateText: (ExprSyntax) -> Expression?
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
            if let value = stateText(argument.expression) {
                return value
            }
            guard let literal = argument.expression.as(StringLiteralExprSyntax.self),
                  let value = literal.representedLiteralValue else {
                error("R.string.literal", "Verbatim text must be a literal without interpolation.",
                      "Use Text(verbatim: \"literal\") for intentional non-localized text", at: argument.expression)
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
        if expression.as(StringLiteralExprSyntax.self) != nil, let value = stateText(expression) {
            if case .interpolatedString = value.value {
                return value
            }
        }
        if let literal = expression.as(StringLiteralExprSyntax.self) {
            if let key = literal.representedLiteralValue, !LocalizationKey.isCanonical(key) {
                let diagnostic = Diagnostic(code: "R.string.invalid_key",
                    message: "String key `\(key)` is not a lowercase dot-separated resource key.",
                    suggestion: "Use lowercase ASCII letter-led segments with only lowercase ASCII letters and digits; dots become underscores in both native catalogs",
                    location: location(of: literal))
                diagnostics.append(diagnostic)
                return nil
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
                          "Use String(localized: \"key\") or SwiftUI Text interpolation with typed scalar arguments", at: call)
                    return nil
                }
                return localizedLiteral(literal)
            default:
                break
            }
        }
        guard let value = scalar(expression), value.type == .string else {
            error("R.string.invalid_key", "This expression does not provide a static localization key.",
                  "Use a static key or Text(verbatim:) for intentional literal text", at: expression)
            return nil
        }
        return value.expression
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
                guard expressions.count == 1, let expression = expressions.first,
                      let value = scalar(expression) else {
                    error("R.string.interpolation", "Localized interpolation must contain one typed scalar expression.",
                          "Use a declared String, Int or Double input without custom formatting", at: segment)
                    return nil
                }
                guard let type = value.type, type != .bool else {
                    error("R.string.interpolation", "Localized interpolation requires a statically known String, Int or Double.",
                          "Declare the interpolated screen input with an explicit supported type", at: expression)
                    return nil
                }
                arguments.append(value.expression)
            }
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
