import RefractIR
import SwiftSyntax

/// A deliberately narrow host ABI. The SwiftUI body is the iOS implementation;
/// the backends emit only these checked values and model callbacks.
struct TextInputHostFrontend {
    struct Result {
        var parameters: [NativeParameter] = [
            NativeParameter(label: "draft", type: .string),
            NativeParameter(label: "focusRequest", type: .int),
            NativeParameter(label: "onDraftCommit", type: .string),
            NativeParameter(label: "onCommit", type: .string),
        ]
        var diagnostics: [Diagnostic] = []
        var isValid: Bool { diagnostics.isEmpty }
    }

    let file: String
    let converter: SourceLocationConverter

    func validate(_ node: StructDeclSyntax, inherited: [String]) -> Result {
        var result = Result()
        guard inherited == ["RefractTextInputHost"] else {
            reject(&result, "A native text-input host must inherit only `RefractTextInputHost`.",
                   "Keep focus and IME policy in the host's ordinary SwiftUI body", node.name)
            return result
        }
        var fields: [String: VariableDeclSyntax] = [:]
        var hasBody = false
        var hasFocusState = false
        for member in node.memberBlock.members {
            guard let declaration = member.decl.as(VariableDeclSyntax.self) else {
                reject(&result, "The text-input host contains an unsupported declaration.",
                       "Use only the documented draft, focusRequest, callbacks, focus state and body", member)
                continue
            }
            for binding in declaration.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                    reject(&result, "The text-input host has an unsupported stored property.",
                           "Use the documented five-input host signature", binding)
                    continue
                }
                if name == "body" {
                    hasBody = binding.accessorBlock != nil
                    continue
                }
                if name == "isHostFocused" {
                    hasFocusState = isFocusState(declaration, binding)
                    if !hasFocusState {
                        reject(&result, "The text-input host requires private native `@FocusState` storage.",
                               "Use `@FocusState private var isHostFocused: Bool`", binding)
                    }
                    continue
                }
                guard fields[name] == nil, let type = hostType(name, declaration, binding) else {
                    reject(&result, "Text-input host property `\(name)` is not part of the bounded contract.",
                           "Use `@Binding var draft: String`, `let focusRequest: Int`, `let onDraftCommit: (String) -> Void`, `let onCommit: () -> Void`, and private `@FocusState var isHostFocused: Bool`", binding)
                    continue
                }
                fields[name] = declaration
                result.parameters[result.parameters.firstIndex { $0.label == name }!] =
                    NativeParameter(label: name, type: type, location: location(binding))
            }
        }
        let names = Set(fields.keys)
        guard names == ["draft", "focusRequest", "onDraftCommit", "onCommit"], hasBody, hasFocusState else {
            reject(&result, "The text-input host must declare its complete five-input signature and SwiftUI body.",
                   "Supply draft, focusRequest, onDraftCommit and onCommit, plus private native focus state", node.name)
            return result
        }
        return result
    }

    func argument(_ argument: LabeledExprSyntax, in builder: Builder) -> NativeArgument? {
        guard let label = argument.label?.text else { return nil }
        let at = location(argument)
        switch label {
        case "draft":
            guard let reference = argument.expression.as(DeclReferenceExprSyntax.self),
                  reference.baseName.text.hasPrefix("$") else { return nil }
            let name = String(reference.baseName.text.dropFirst())
            guard builder.currentStates.contains(where: {
                switch $0 {
                case let .binding(declared, .string, _): declared == name
                default: false
                }
            }) else { return nil }
            return NativeArgument(label: label,
                expression: Expression(.valueProperty(.binding(name)), type: .string, location: at),
                type: .string, location: at)
        case "focusRequest":
            guard argument.expression.as(DeclReferenceExprSyntax.self) != nil,
                  let value = builder.scalar(argument.expression), value.type == .int,
                  case let .valueProperty(.binding(name)) = value.expression.value else { return nil }
            return NativeArgument(label: label,
                expression: Expression(.valueProperty(.binding(name)), type: .int, location: at),
                type: .int, location: at)
        case "onDraftCommit", "onCommit":
            guard let closure = argument.expression.as(ClosureExprSyntax.self),
                  let action = actionReference(closure, takesDraft: label == "onDraftCommit", builder: builder) else {
                return nil
            }
            return NativeArgument(label: label,
                expression: Expression(.reference(action), location: at),
                parameterType: label == "onDraftCommit" ? .actionString : .action, location: at)
        default:
            return nil
        }
    }

    private func actionReference(_ closure: ClosureExprSyntax, takesDraft: Bool,
                                 builder: Builder) -> String? {
        guard closure.statements.count == 1,
              let call = closure.statements.first?.item.as(ExprSyntax.self)?.as(FunctionCallExprSyntax.self),
              call.trailingClosure == nil,
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.argumentNames == nil,
              let model = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let reference = builder.currentModels.first(where: { $0.propertyName == model }),
              let contract = builder.models.first(where: { $0.name == reference.protocolName }),
              let action = contract.actions.first(where: { $0.name == member.declName.baseName.text }) else {
            return nil
        }
        let expectedCount = takesDraft ? 1 : 0
        guard action.parameters.count == expectedCount, call.arguments.count == expectedCount else { return nil }
        if takesDraft {
            guard let closureName = closureParameter(closure) else { return nil }
            guard let parameter = action.parameters.first, parameter.type == .string,
                  let supplied = call.arguments.first,
                  supplied.label?.text == parameter.externalName,
                  let value = supplied.expression.as(DeclReferenceExprSyntax.self) else { return nil }
            let name = value.baseName.text
            guard name == closureName else { return nil }
        } else if closure.signature?.parameterClause != nil {
            return nil
        }
        return "\(model).\(action.name)"
    }

    private func closureParameter(_ closure: ClosureExprSyntax) -> String? {
        guard let parameters = closure.signature?.parameterClause else { return "$0" }
        switch parameters {
        case let .parameterClause(clause):
            guard clause.parameters.count == 1, clause.parameters.first?.secondName == nil else { return nil }
            return clause.parameters.first?.firstName.text
        case let .simpleInput(input):
            guard input.count == 1 else { return nil }
            return input.first?.name.text
        }
    }

    private func hostType(_ name: String, _ declaration: VariableDeclSyntax,
                          _ binding: PatternBindingSyntax) -> ValueType? {
        let type = binding.typeAnnotation?.type.trimmedDescription
        if name == "draft" {
            return declaration.attributes.trimmedDescription == "@Binding"
                && declaration.bindingSpecifier.tokenKind == .keyword(.var)
                && binding.initializer == nil && binding.accessorBlock == nil && type == "String" ? .string : nil
        }
        guard declaration.bindingSpecifier.tokenKind == .keyword(.let), declaration.attributes.isEmpty,
              binding.initializer == nil, binding.accessorBlock == nil else { return nil }
        switch name {
        case "focusRequest" where type == "Int": return .int
        case "onDraftCommit" where type == "(String) -> Void": return .string
        case "onCommit" where type == "() -> Void": return .string
        default: return nil
        }
    }

    private func isFocusState(_ declaration: VariableDeclSyntax,
                              _ binding: PatternBindingSyntax) -> Bool {
        declaration.attributes.trimmedDescription == "@FocusState"
            && declaration.modifiers.contains { $0.name.tokenKind == .keyword(.private) }
            && declaration.bindingSpecifier.tokenKind == .keyword(.var)
            && binding.typeAnnotation?.type.trimmedDescription == "Bool"
            && binding.initializer == nil && binding.accessorBlock == nil
    }

    private func reject(_ result: inout Result, _ message: String, _ suggestion: String,
                        _ node: some SyntaxProtocol) {
        result.diagnostics.append(Diagnostic(code: "RFINPUT001", message: message,
            suggestion: suggestion, location: location(node)))
    }

    private func location(_ node: some SyntaxProtocol) -> RefractIR.SourceLocation {
        let position = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        return RefractIR.SourceLocation(file: file, line: position.line, column: position.column)
    }
}
