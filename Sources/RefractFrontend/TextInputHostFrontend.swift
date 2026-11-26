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
                    hasBody = true
                    let bodyError = nativeBodyError(declaration, binding)
                    if let bodyError {
                        reject(&result, "The text-input host body \(bodyError).",
                               "Use TextField(\"Message\", text: $draft).focused($isHostFocused).submitLabel(.done), update focus on focusRequest, then publish onDraftCommit(draft) before onCommit() in onSubmit", binding)
                    }
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
        if names == ["draft", "focusRequest", "onDraftCommit", "onCommit"], hasFocusState, hasBody, !result.diagnostics.isEmpty {
            return result
        }
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
            if label == "onCommit" {
                return NativeArgument(label: label, action: action, type: .action, location: at)
            }
            return NativeArgument(label: label, action: action, type: .actionString, location: at)
        default:
            return nil
        }
    }

    private func actionReference(_ closure: ClosureExprSyntax, takesDraft: Bool,
                                 builder: Builder) -> StateAction? {
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
        return .modelMethod(model: model, name: action.name, arguments: [])
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

    /// Check the native implementation without translating it into generated child views.
    /// Match syntax nodes rather than source text so ordinary whitespace and multiline closures
    /// do not change acceptance; arbitrary modifier or statement behavior remains outside this ABI.
    private func nativeBodyError(_ declaration: VariableDeclSyntax,
                                 _ binding: PatternBindingSyntax) -> String? {
        guard declaration.bindingSpecifier.tokenKind == .keyword(.var), declaration.attributes.isEmpty,
              declaration.modifiers.isEmpty, declaration.bindings.count == 1,
              binding.typeAnnotation?.type.trimmedDescription == "some View", binding.initializer == nil,
              let accessors = binding.accessorBlock?.accessors,
              case let .getter(statements) = accessors, statements.count == 1,
              let expression = bodyExpression(statements.first!) else {
            return "must be a computed `some View` with one native TextField expression"
        }
        guard let onSubmitCall = unwrapped(expression).as(FunctionCallExprSyntax.self),
              let onSubmitReceiver = modifierReceiver(onSubmitCall, named: "onSubmit"),
              onSubmitCall.arguments.isEmpty, onSubmitCall.additionalTrailingClosures.isEmpty,
              isOrderedSubmit(onSubmitCall.trailingClosure) else {
            return "must finish with onSubmit publishing onDraftCommit(draft) before onCommit()"
        }
        guard let onChangeCall = onSubmitReceiver.as(FunctionCallExprSyntax.self),
              let onChangeReceiver = modifierReceiver(onChangeCall, named: "onChange"),
              onChangeCall.arguments.count == 1, onChangeCall.arguments.first?.label?.text == "of",
              onChangeCall.arguments.first.map({ reference($0.expression, named: "focusRequest") }) == true,
              onChangeCall.additionalTrailingClosures.isEmpty,
              isFocusRequestChange(onChangeCall.trailingClosure) else {
            return "must set isHostFocused to true on each changed focusRequest"
        }
        guard let submitLabelCall = onChangeReceiver.as(FunctionCallExprSyntax.self),
              let submitLabelReceiver = modifierReceiver(submitLabelCall, named: "submitLabel"),
              submitLabelCall.trailingClosure == nil, submitLabelCall.additionalTrailingClosures.isEmpty,
              submitLabelCall.arguments.count == 1, submitLabelCall.arguments.first?.label == nil,
              submitLabelCall.arguments.first?.expression.trimmedDescription == ".done" else {
            return "must declare submitLabel(.done) before its focus-token observer"
        }
        guard let focusedCall = submitLabelReceiver.as(FunctionCallExprSyntax.self),
              let input = modifierReceiver(focusedCall, named: "focused")?.as(FunctionCallExprSyntax.self),
              focusedCall.trailingClosure == nil, focusedCall.additionalTrailingClosures.isEmpty,
              isProjection(focusedCall.arguments, named: "isHostFocused") else {
            return "must attach focused($isHostFocused) to the native input"
        }
        guard input.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "TextField",
              isDraftTextField(input) else {
            return "must use TextField(\"Message\", text: $draft) without additional input arguments"
        }
        return nil
    }

    private func modifierReceiver(_ call: FunctionCallExprSyntax, named name: String) -> ExprSyntax? {
        guard let member = unwrapped(call.calledExpression).as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == name, member.declName.argumentNames == nil,
              let receiver = member.base else { return nil }
        return unwrapped(receiver)
    }

    private func isDraftTextField(_ call: FunctionCallExprSyntax) -> Bool {
        guard call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              call.arguments.count == 2, call.arguments.first?.label == nil,
              unwrapped(call.arguments.first!.expression).as(StringLiteralExprSyntax.self)?.representedLiteralValue == "Message",
              let text = call.arguments.last, text.label?.text == "text" else { return false }
        return projection(text.expression, named: "draft")
    }

    private func isProjection(_ arguments: LabeledExprListSyntax, named name: String) -> Bool {
        guard arguments.count == 1, arguments.first?.label == nil else { return false }
        return projection(arguments.first!.expression, named: name)
    }

    private func isFocusRequestChange(_ closure: ClosureExprSyntax?) -> Bool {
        guard let closure, isFocusChangeSignature(closure.signature),
              closure.statements.count == 1,
              let expression = closure.statements.first?.item.as(ExprSyntax.self),
              let sequence = unwrapped(expression).as(SequenceExprSyntax.self) else { return false }
        let elements = Array(sequence.elements)
        return elements.count == 3
            && reference(elements[0], named: "isHostFocused")
            && elements[1].as(AssignmentExprSyntax.self) != nil
            && unwrapped(elements[2]).as(BooleanLiteralExprSyntax.self)?.literal.tokenKind == .keyword(.true)
    }

    private func isFocusChangeSignature(_ signature: ClosureSignatureSyntax?) -> Bool {
        guard let signature, signature.attributes.isEmpty, signature.effectSpecifiers == nil,
              signature.capture == nil, hasVoidReturn(signature.returnClause),
              let parameters = signature.parameterClause else { return false }
        switch parameters {
        case let .simpleInput(input):
            return input.map(\.name.tokenKind) == [.wildcard, .wildcard]
        case let .parameterClause(clause):
            guard clause.parameters.count == 2 else { return false }
            return clause.parameters.allSatisfy {
                $0.attributes.isEmpty && $0.modifiers.isEmpty && $0.secondName == nil
                    && $0.ellipsis == nil && $0.type?.trimmedDescription == "Int"
            }
        }
    }

    private func isOrderedSubmit(_ closure: ClosureExprSyntax?) -> Bool {
        guard let closure, closure.statements.count == 2,
              isEmptyVoidSignature(closure.signature) else { return false }
        return isCall(closure.statements.first!, name: "onDraftCommit", argument: "draft")
            && isCall(closure.statements.last!, name: "onCommit", argument: nil)
    }

    private func isEmptyVoidSignature(_ signature: ClosureSignatureSyntax?) -> Bool {
        guard let signature else { return true }
        guard signature.attributes.isEmpty, signature.capture == nil, signature.effectSpecifiers == nil,
              hasVoidReturn(signature.returnClause), let parameters = signature.parameterClause else { return false }
        switch parameters {
        case let .parameterClause(clause): return clause.parameters.isEmpty
        case let .simpleInput(input): return input.isEmpty
        }
    }

    private func hasVoidReturn(_ clause: ReturnClauseSyntax?) -> Bool {
        clause == nil || clause?.type.trimmedDescription == "Void"
    }

    private func isCall(_ statement: CodeBlockItemSyntax, name: String, argument: String?) -> Bool {
        guard let expression = statement.item.as(ExprSyntax.self),
              let call = unwrapped(expression).as(FunctionCallExprSyntax.self),
              reference(call.calledExpression, named: name),
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              call.arguments.count == (argument == nil ? 0 : 1) else { return false }
        guard let argument else { return true }
        return call.arguments.first?.label == nil
            && reference(call.arguments.first!.expression, named: argument)
    }

    private func bodyExpression(_ statement: CodeBlockItemSyntax) -> ExprSyntax? {
        statement.item.as(ExprSyntax.self) ?? statement.item.as(ReturnStmtSyntax.self)?.expression
    }

    private func reference(_ expression: ExprSyntax, named name: String) -> Bool {
        let expression = unwrapped(expression)
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text == name && reference.argumentNames == nil
        }
        guard let member = expression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == name, member.declName.argumentNames == nil,
              let base = member.base else { return false }
        return unwrapped(base).as(DeclReferenceExprSyntax.self)?.baseName.text == "self"
    }

    private func projection(_ expression: ExprSyntax, named name: String) -> Bool {
        let expression = unwrapped(expression)
        if reference(expression, named: "$" + name) { return true }
        guard let member = expression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == name, member.declName.argumentNames == nil,
              let base = member.base else { return false }
        return projection(base, named: "self")
    }

    private func unwrapped(_ expression: ExprSyntax) -> ExprSyntax {
        guard let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
              tuple.elements.first?.label == nil, let element = tuple.elements.first?.expression else { return expression }
        return unwrapped(element)
    }

    private func hostType(_ name: String, _ declaration: VariableDeclSyntax,
                          _ binding: PatternBindingSyntax) -> NativeParameterType? {
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
