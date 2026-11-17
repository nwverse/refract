import RefractIR
import SwiftSyntax

extension Builder {
    func navigationStack(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.count == 1, call.arguments.first?.label?.text == "path",
              let projection = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
              projection.baseName.text.hasPrefix("$"), call.trailingClosure != nil,
              call.additionalTrailingClosures.isEmpty else {
            error("RFNAV001", "NavigationStack requires one `path: $path` binding to a local destination array.",
                  "Use `NavigationStack(path: $path) { ... }` with `@State private var path: [Route] = []`", at: call)
            return nil
        }
        let pathName = String(projection.baseName.text.dropFirst())
        guard let path = currentStates.compactMap({ state -> (String, String)? in
            guard case let .navigationPath(name, enumName, _) = state else { return nil }
            return (name, enumName)
        }).first, path.0 == pathName else {
            error("RFNAV002", "NavigationStack path must be the declared local `[Destination]` @State array.",
                  "Use `@State private var path: [Route] = []`; the native host owns its contents", at: projection)
            return nil
        }
        guard let declaration = enums.first(where: { $0.name == path.1 }), declaration.isNavigationDestination,
              declaration.payloadTypes.isEmpty else {
            error("RFNAV002", "Navigation destinations need a local `Hashable` enum without payloads.",
                  "Use `enum Route: Hashable { case detail }` and pass typed data through a destination model", at: projection)
            return nil
        }
        var destinations: [NavigationDestination] = []
        pendingNavigationDestinations = []
        for statement in call.trailingClosure!.statements {
            guard let child = viewStatement(statement) else {
                pendingNavigationDestinations = []
                error("RFNAV001", "NavigationStack accepts supported content with one navigationDestination registration.",
                      "Use VStack { NavigationLink(...) }.navigationDestination(for: Route.self) { route in ... }", at: statement)
                return nil
            }
            content.append(child)
        }
        destinations = pendingNavigationDestinations
        pendingNavigationDestinations = []
        guard Set(destinations.map(\.caseName)).count == destinations.count,
              Set(destinations.map(\.caseName)) == Set(declaration.cases) else {
            error("RFNAV003", "Navigation destinations must cover every enum case exactly once.",
                  "Declare one static case and typed destination view for every case of `\(declaration.name)`", at: call)
            return nil
        }
        for link in content {
            guard case let .navigationLink(_, value, _) = link, declaration.cases.contains(value) else {
                error("RFNAV003", "A NavigationLink value must be a case of the stack's destination enum.",
                      "Use a static case declared by `\(declaration.name)`", at: call)
                return nil
            }
        }
        return .navigationStack(NavigationStackNode(pathName: pathName, enumName: declaration.name,
                                                   content: content, destinations: destinations),
                                location: location(of: call))
    }

    func navigationLink(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard call.arguments.count == 1, call.arguments[0].label == nil,
              let member = call.arguments[0].expression.as(MemberAccessExprSyntax.self),
              member.base == nil, member.declName.argumentNames == nil,
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else {
              member.base == nil, member.declName.argumentNames == nil else {
            error("RFNAV001", "NavigationLink accepts one localized title and a static `.case` value.",
                  "Use `NavigationLink(\"navigation.open\", value: .detail)`; dynamic strings and closure destinations are unsupported", at: call)
            return nil
        }
        let title: Expression
        if let value = call.arguments.first(where: { $0.label?.text == "value" }) {
            guard call.arguments.count == 2, call.arguments[0].label == nil,
                  call.arguments[1].label?.text == "value",
                  let member = value.expression.as(MemberAccessExprSyntax.self), member.base == nil,
                  member.declName.argumentNames == nil else { return nil }
            _ = member
        }
        if let key = stringLiteral(call.arguments[0].expression), LocalizationKey.isCanonical(key) {
            title = Expression(.localizedText(LocalizedText(key: key)), type: .string, location: location(of: call))
        } else {
            error("RFNAV001", "NavigationLink needs a canonical localized title.",
                  "Use `NavigationLink(\"navigation.open\", value: .detail)` with a resource key", at: call)
            return nil
        }
        guard let member = call.arguments.last?.expression.as(MemberAccessExprSyntax.self) else { return nil }
        return .navigationLink(title: title, destination: member.declName.baseName.text, location: location(of: call))
    }

    func navigationDestination(_ call: FunctionCallExprSyntax, on node: ViewNode) -> ViewNode? {
        guard case .stack = node else {
            error("RFNAV001", "navigationDestination must be attached to the NavigationStack's root VStack.",
                  "Use `VStack { NavigationLink(...) }.navigationDestination(for: Route.self) { route in ... }`", at: call)
            return nil
        }
        guard pendingNavigationDestinations.isEmpty, let enumName = currentStates.compactMap({ state -> String? in
            guard case let .navigationPath(_, enumName, _) = state else { return nil }
            return enumName
        }).first, let declaration = enums.first(where: { $0.name == enumName }) else {
            error("RFNAV001", "navigationDestination requires a NavigationStack path enum and one registration.",
                  "Attach it to the root VStack of `NavigationStack(path:)`", at: call)
            return nil
        }
        let cases = declaration.cases
        guard call.arguments.count == 1,
        guard call.arguments.count == 1, call.arguments.first?.label?.text == "for",
              call.arguments.first?.expression.trimmedDescription == "\(enumName).self",
              let closure = call.trailingClosure, call.additionalTrailingClosures.isEmpty else {
            error("RFNAV001", "Use `navigationDestination(for: Route.self) { route in switch route ... }`.",
                  "Register one finite destination enum and exhaustive typed branches", at: call)
            return nil
        }
        guard let signature = closure.signature,
              let parameter = signature.parameterClause?.as(ClosureShorthandParameterListSyntax.self),
              parameter.count == 1, parameter.first?.name.text == "route",
              closure.statements.count == 1,
              let switchStatement = closure.statements.first?.item.as(SwitchExprSyntax.self),
              switchStatement.subject.as(DeclReferenceExprSyntax.self)?.baseName.text == "route" else {
            error("RFNAV001", "Destination content must switch exhaustively over the `route` closure argument.",
                  "Use `{ route in switch route { case .detail: DetailScreen(model: model) } }`", at: closure)
            return nil
        }
        var destinations: [NavigationDestination] = []
        for item in switchStatement.cases {
            guard let item = item.as(SwitchCaseSyntax.self),
                  let label = item.label.as(SwitchCaseLabelSyntax.self), label.caseItems.count == 1,
                  let pattern = label.caseItems.first?.pattern.as(ExpressionPatternSyntax.self),
                  let member = pattern.expression.as(MemberAccessExprSyntax.self),
                  member.base == nil, member.declName.argumentNames == nil,
                  cases.contains(member.declName.baseName.text), item.statements.count == 1,
                  let viewCall = item.statements.first?.item.as(FunctionCallExprSyntax.self),
                  let viewName = viewCall.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
                  viewCall.trailingClosure == nil, viewCall.additionalTrailingClosures.isEmpty else {
                error("RFNAV003", "A destination case must contain one static enum case and one typed destination view.",
                      "Use `.detail: DetailScreen(model: model)` or a declared zero-argument `RefractNativeView`", at: item)
                return nil
            }
            if interop.declarations.contains(where: { $0.name == viewName }) {
                guard viewCall.arguments.isEmpty else {
                    error("RFNAV003", "This bounded native destination accepts no arguments.",
                          "Use a zero-argument `RefractNativeView` for a native escape-hatch destination", at: viewCall)
                    return nil
                }
                destinations.append(NavigationDestination(caseName: member.declName.baseName.text, viewName: viewName))
                continue
            }
            guard let declaration = viewDeclarations[viewName], viewName != currentViewName,
                  let model = navigationModelInput(viewCall, declaration: declaration) else {
                error("RFNAV003", "Destination `\(viewName)` must be a same-file generated View with one declared model input.",
                      "Use `DetailScreen(model: model)` or a zero-argument `RefractNativeView`; do not use a runtime registry", at: viewCall)
                return nil
            }
            destinations.append(NavigationDestination(caseName: member.declName.baseName.text,
                                                     viewName: viewName, model: model))
        }
        pendingNavigationDestinations = destinations
        return node
    }

    private func navigationModelInput(_ call: FunctionCallExprSyntax,
                                      declaration: StructDeclSyntax) -> ChildView.Argument? {
        guard call.arguments.count == 1, let argument = call.arguments.first,
              let label = argument.label?.text,
              let reference = argument.expression.as(DeclReferenceExprSyntax.self),
              let model = currentModels.first(where: { $0.propertyName == reference.baseName.text }),
              declaration.memberBlock.members.contains(where: { member in
                guard let variable = member.decl.as(VariableDeclSyntax.self),
                      variable.bindingSpecifier.tokenKind == .keyword(.let), variable.attributes.isEmpty,
                      let binding = variable.bindings.first,
                      binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == label,
                      binding.typeAnnotation?.type.trimmedDescription == model.protocolName else { return false }
                return true
              }) else { return nil }
        return ChildView.Argument(label: label, expression: model.propertyName)
    }
}
