import RefractIR
import SwiftSyntax

extension Builder {
    func validateModalDeclarations(_ module: Module) {
        for screen in module.screens {
            if screen.modals.count > 1 {
                let names = screen.modals.map(\.stateName)
                if names.count != Set(names).count {
                    diagnostics.append(Diagnostic(code: "RFMODAL003",
                        message: "A native modal host needs a distinct Boolean owner for each presentation.",
                        suggestion: "Use one sheet and one confirmation alert with separate declared Boolean state",
                        location: screen.location))
                }
            }
            for modal in screen.modals where modal.kind == .alert {
                let eventName = "on\(modal.stateName.prefix(1).uppercased())\(modal.stateName.dropFirst())Present"
                if screen.parameters.contains(where: { $0.name == eventName }) || screen.states.contains(where: {
                    switch $0 {
                    case let .model(reference, _): reference.propertyName == eventName
                    case let .binding(name, _, _), let .navigationPath(name, _, _), let .tabSelection(name, _, _): name == eventName
                    case let .state(name, _, _, _): name == eventName
                    }
                }) {
                    diagnostics.append(Diagnostic(code: "RFMODAL003",
                        message: "Generated modal event `\(eventName)` conflicts with a declared input.",
                        suggestion: "Rename the modal Boolean owner so its typed native event has a unique name",
                        location: screen.location))
                }
            }
        }
    }

    func modal(_ call: FunctionCallExprSyntax, name: String, on node: ViewNode) -> ViewNode? {
        switch node {
        case .stack, .layout, .scroll, .list:
            break
        default:
            modalError("RFMODAL003", "A modal modifier must attach to a supported container root, not a control or leaf view.",
                       "Wrap the screen content in VStack/HStack/ZStack and attach sheet/alert to that container", at: call)
            return nil
        }
        guard node.children.allSatisfy({ $0.containsModal == false }) else {
            modalError("RFMODAL003", "A modal host cannot be nested inside another modal host.",
                       "Keep one sheet and one confirmation alert on a single ordinary root view", at: call)
            return nil
        }
        guard let modal = name == "sheet" ? sheet(call) : confirmationAlert(call) else { return nil }
        currentModals.append(modal)
        return node
    }

    private func sheet(_ call: FunctionCallExprSyntax) -> ModalPresentation? {
        let arguments = Array(call.arguments)
        guard arguments.map(\.label?.text) == ["isPresented"], call.additionalTrailingClosures.isEmpty,
              let closure = call.trailingClosure else {
            modalError("RFMODAL001", "This sheet slice accepts only `.sheet(isPresented: $state) { content }`.",
                       "Use a declared Boolean @State/@Binding and one supported content builder", at: call)
            return nil
        }
        guard let owner = modalOwner(arguments[0].expression) else { return nil }
        guard let content = children(of: closure), content.count == 1, !content.isEmpty else {
            modalError("RFMODAL001", "Sheet content must contain one supported view.",
                       "Use the existing bounded View subset inside a single content builder", at: closure)
            return nil
        }
        guard content.allSatisfy({ $0.containsModal == false }) else { return nil }
        return ModalPresentation(kind: .sheet, stateName: owner.name, isBinding: owner.isBinding,
                                 content: content)
    }

    private func confirmationAlert(_ call: FunctionCallExprSyntax) -> ModalPresentation? {
        let arguments = Array(call.arguments)
        guard arguments.map(\.label?.text) == [nil, "isPresented"], call.trailingClosure != nil,
              call.additionalTrailingClosures.map(\.label.text) == ["message"],
              let title = localizedModalText(arguments[0].expression),
              let owner = modalOwner(arguments[1].expression),
              let actionClosure = call.trailingClosure,
              let messageClosure = call.additionalTrailingClosures.first?.closure else {
            modalError("RFMODAL002", "This alert accepts one title, a Boolean binding, two actions and one message.",
                       "Use `.alert(\"key\", isPresented: $state) { Button(\"confirm.key\") { model.confirm() }; Button(\"cancel.key\", role: .cancel) {} } message: { Text(\"message.key\") }`", at: call)
            return nil
        }
        let actions = Array(actionClosure.statements)
        guard actions.count == 2, let first = actions[0].item.as(FunctionCallExprSyntax.self),
              let second = actions[1].item.as(FunctionCallExprSyntax.self),
              let confirm = alertButton(first, role: nil),
              let cancel = alertButton(second, role: "cancel") else {
            modalError("RFMODAL002", "A confirmation alert needs one model-action Button and one cancel-role Button.",
                       "Use two ordinary SwiftUI alert buttons with localized titles; the second must have role .cancel", at: actionClosure)
            return nil
        }
        guard messageClosure.statements.count == 1,
              let messageCall = messageClosure.statements.first?.item.as(FunctionCallExprSyntax.self),
              messageCall.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Text",
              messageCall.trailingClosure == nil, messageCall.arguments.count == 1,
              let messageArgument = messageCall.arguments.first,
              let message = localizedModalText(messageArgument.expression) else {
            modalError("RFMODAL002", "Alert message must be one localized static `Text` view.",
                       "Use `message: { Text(\"message.key\") }`", at: messageClosure)
            return nil
        }
        return ModalPresentation(kind: .alert, stateName: owner.name, isBinding: owner.isBinding,
                                 title: title, message: message, confirmTitle: confirm.title,
                                 cancelTitle: cancel.title, confirmAction: confirm.action)
    }

    private func alertButton(_ call: FunctionCallExprSyntax, role: String?) -> (title: Expression, action: StateAction?)? {
        let arguments = Array(call.arguments)
        guard call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Button",
              arguments.count == (role == nil ? 1 : 2), arguments[0].label == nil,
              let title = localizedModalText(arguments[0].expression),
              call.additionalTrailingClosures.isEmpty else { return nil }
        if let role {
            guard arguments[1].label?.text == "role",
                  arguments[1].expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == role,
                  arguments[1].expression.as(MemberAccessExprSyntax.self)?.base == nil,
                  call.trailingClosure?.statements.isEmpty == true else { return nil }
            return (title, nil)
        }
        guard call.trailingClosure?.statements.count == 1,
              let expression = call.trailingClosure?.statements.first?.item.as(ExprSyntax.self),
              let action = modelAction(expression) else { return nil }
        return (title, action)
    }

    private func modalOwner(_ expression: ExprSyntax) -> (name: String, isBinding: Bool)? {
        guard let reference = expression.as(DeclReferenceExprSyntax.self),
              reference.baseName.text.hasPrefix("$") else {
            modalError("RFMODAL001", "Modal presentation requires a projected Boolean @State or @Binding.",
                       "Use `isPresented: $state`; constants, layout flags and arbitrary expressions are not modal hosts", at: expression)
            return nil
        }
        let name = String(reference.baseName.text.dropFirst())
        for state in currentStates {
            switch state {
            case let .state(stateName, .bool, _, _) where stateName == name: return (name, false)
            case let .binding(stateName, .bool, _) where stateName == name: return (name, true)
            default: continue
            }
        }
        modalError("RFMODAL001", "Modal state `\(name)` is not a declared Boolean @State or @Binding.",
                   "Declare the modal's typed Boolean owner before using its `$` projection", at: expression)
        return nil
    }

    private func localizedModalText(_ expression: ExprSyntax) -> Expression? {
        guard let literal = expression.as(StringLiteralExprSyntax.self),
              let key = stringLiteral(expression), LocalizationKey.isCanonical(key) else {
            modalError("RFMODAL002", "Modal title, message and action labels need static localized resource keys.",
                       "Use a canonical lowercase resource key and declare it in both platform catalogs", at: expression)
            return nil
        }
        return Expression(.localizedText(LocalizedText(key: key)), type: .string, location: location(of: literal))
    }

    private func modalError(_ code: String, _ message: String, _ suggestion: String,
                            at node: some SyntaxProtocol) {
        guard !diagnostics.contains(where: { $0.code == code && $0.location == location(of: node) }) else { return }
        error(code, message, suggestion, at: node)
    }
}

extension ViewNode {
    var containsModal: Bool {
        switch self {
        case let .stack(_, children, _, _), let .layout(_, children, _, _), let .list(children, _, _):
            return children.contains(where: \.containsModal)
        case let .scroll(_, child, _, _), let .listItem(child, _), let .nativeModifier(child, _, _):
            return child.containsModal
        case let .button(label, _, _, _): return label.containsModal
        case let .section(_, children, _): return children.contains(where: \.containsModal)
        case let .component(component, _): return component.children.contains(where: \.containsModal)
        case let .forEach(items, _): return items.content.containsModal
        case let .conditional(branches, _): return branches.contains { $0.children.contains(where: \.containsModal) }
        case let .optionalBinding(_, _, children, otherwise, _):
            return children.contains(where: \.containsModal) || otherwise.contains(where: \.containsModal)
        case let .switchExpression(_, _, cases, _): return cases.contains { $0.children.contains(where: \.containsModal) }
        case let .navigationStack(stack, _): return stack.content.contains(where: \.containsModal)
        case let .platformView(alternatives, _):
            return (alternatives.ios + alternatives.android + alternatives.harmonyOS).contains(where: \.containsModal)
        default: return false
        }
    }
}
