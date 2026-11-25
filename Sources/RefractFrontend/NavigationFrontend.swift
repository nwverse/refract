import RefractIR
import SwiftSyntax

extension Builder {
    /// Registers the complete same-file View table before the first body resolves a later destination.
    func collectDeclaredViews(_ tree: SourceFileSyntax) {
        for statement in tree.statements {
            guard let declaration = statement.item.as(StructDeclSyntax.self),
                  declaration.inheritanceClause?.inheritedTypes.contains(where: {
                      $0.type.trimmedDescription == "View"
                  }) == true else { continue }
            viewDeclarations[declaration.name.text] = declaration
        }
    }

    /// Binds child links to the one source graph after all destination switches are known.
    /// The graph owns identity; each generated destination receives only a typed callback.
    func bindNavigationDestinations(_ module: Module) {
        let stacks = module.screens.compactMap { screen -> NavigationStackNode? in
            guard case let .navigationStack(stack, _) = screen.body else { return nil }
            return stack
        }
        var bindings: [String: NavigationOperation] = [:]
        for stack in stacks {
            for destination in stack.destinations {
                guard let screen = module.screens.first(where: { $0.name == destination.viewName }),
                      containsNavigationLink(screen.body) else { continue }
                let operation = NavigationOperation(pathName: stack.pathName, enumName: stack.enumName)
                if let existing = bindings[screen.name], existing != operation {
                    diagnostics.append(Diagnostic(code: "RFNAV003",
                        message: "A linked destination cannot belong to two different navigation graphs.",
                        suggestion: "Use one finite enum and one host callback for this destination graph.",
                        location: screen.location))
                } else {
                    bindings[screen.name] = operation
                }
            }
        }
        // Rejected link syntax has no IR, but its source View still lacks a host callback.
        // Report that independent graph error rather than silently treating it as a leaf screen.
        let registeredDestinationNames = Set(stacks.flatMap { $0.destinations.map(\.viewName) })
        for (name, declaration) in viewDeclarations {
            guard registeredDestinationNames.contains(name),
                  !module.screens.contains(where: { $0.name == name }), containsNavigationLinkSyntax(declaration) else { continue }
            diagnostics.append(Diagnostic(code: "RFNAV003",
                message: "A destination NavigationLink must use the enclosing graph's finite enum.",
                suggestion: "Use `NavigationLink(\"navigation.open\", value: Route.case)` and register that destination in the same source file.",
                location: location(of: declaration.name)))
        }
        screens = module.screens.map { screen in
            guard containsNavigationLink(screen.body) else {
                return Screen(name: screen.name, parameters: screen.parameters, states: screen.states, modals: screen.modals,
                              navigation: bindings[screen.name], body: screen.body,
                              nativeValues: screen.nativeValues, lifecycle: screen.lifecycle, location: screen.location)
            }
            if let operation = bindings[screen.name] {
                func bindList(_ items: ListItems) -> ListItems? {
                    bind(items.content).map { content in
                        ListItems(collection: items.collection, itemName: items.itemName, itemType: items.itemType,
                                  key: items.key, keyType: items.keyType, content: content, contentType: items.contentType,
                                  projection: items.projection, modelType: items.modelType,
                                  messageBlocks: items.messageBlocks, location: items.location)
                    }
                }
                func bind(_ node: ViewNode) -> ViewNode? {
                    if case let .navigationLink(title, pathName, enumName, destination, location) = node {
                        // A qualified child link starts with the conventional placeholder in `navigationLink(_:)`.
                        // Resolve it here, while the actual enclosing graph is known; backends never accept a wildcard.
                        guard pathName == "path" || pathName == operation.pathName,
                              enumName == operation.enumName,
                              enums.first(where: { $0.name == enumName })?.cases.contains(destination) == true else {
                            diagnostics.append(Diagnostic(code: "RFNAV003",
                                message: "A linked destination must stay within its host's finite destination enum.",
                                suggestion: "Use only registered cases of `\(operation.enumName)`", location: location))
                            return nil
                        }
                        return .navigationLink(title: title, pathName: operation.pathName, enumName: operation.enumName,
                                               destination: destination, location: location)
                    }
                    switch node {
                    case let .stack(axis, children, modifiers, location):
                        return .stack(axis: axis, children: children.compactMap(bind), modifiers: modifiers, location: location)
                    case let .scroll(axis, child, modifiers, location):
                        return bind(child).map { .scroll(axis: axis, child: $0, modifiers: modifiers, location: location) }
                    case let .button(label, action, modifiers, location):
                        return bind(label).map { .button(label: $0, action: action, modifiers: modifiers, location: location) }
                    case let .nativeModifier(child, operations, location):
                        return bind(child).map { .nativeModifier(child: $0, operations: operations, location: location) }
                    case let .component(component, location):
                        let bound = ComponentReference(name: component.name, arguments: component.arguments,
                            children: component.children.compactMap(bind), modifiers: component.modifiers)
                        return .component(bound, location: location)
                    case let .platformView(alternatives, location):
                        let bound = PlatformAlternatives(ios: alternatives.ios.compactMap(bind),
                            android: alternatives.android.compactMap(bind), harmonyOS: alternatives.harmonyOS.compactMap(bind))
                        return .platformView(bound, location: location)
                    case let .conditional(branches, location):
                        let bound = branches.map {
                            ViewNode.ConditionBranch(condition: $0.condition, children: $0.children.compactMap(bind))
                        }
                        return .conditional(conditions: bound, location: location)
                    case let .optionalBinding(subject, binding, children, otherwise, location):
                        return .optionalBinding(subject: subject, binding: binding, children: children.compactMap(bind),
                                                otherwise: otherwise.compactMap(bind), location: location)
                    case let .switchExpression(subject, enumName, cases, location):
                        let bound = cases.map {
                            SwitchCase(name: $0.name, binding: $0.binding, children: $0.children.compactMap(bind))
                        }
                        return .switchExpression(subject: subject, enumName: enumName, cases: bound, location: location)
                    case let .layout(layout, children, modifiers, location):
                        return .layout(layout, children: children.compactMap(bind), modifiers: modifiers, location: location)
                    case let .list(children, modifiers, location):
                        return .list(children: children.compactMap(bind), modifiers: modifiers, location: location)
                    case let .messageBlocks(nested, location):
                        return bindList(nested.items).map {
                            .messageBlocks(NestedListItems($0, parent: nested.parent, message: nested.message,
                                                           block: nested.block), location: location)
                        }
                    case let .section(header, children, location):
                        return .section(header: header, children: children.compactMap(bind), location: location)
                    case let .listItem(child, location):
                        return bind(child).map { .listItem(child: $0, location: location) }
                    case let .forEach(items, location):
                        return bindList(items).map { .forEach($0, location: location) }
                    case let .horizontalSections(sections, location):
                        return bind(sections.rows.content).map { content in
                            let rows = HorizontalItemCollection(property: sections.rows.property, itemName: sections.rows.itemName,
                                itemType: sections.rows.itemType, key: sections.rows.key, keyType: sections.rows.keyType,
                                content: content, location: sections.rows.location)
                            return .horizontalSections(HorizontalSectionCollection(collection: sections.collection,
                                modelType: sections.modelType, sectionName: sections.sectionName,
                                sectionType: sections.sectionType, sectionKey: sections.sectionKey,
                                sectionKeyType: sections.sectionKeyType, titleProperty: sections.titleProperty,
                                rows: rows, location: sections.location), location: location)
                        }
                    case let .navigationStack(stack, location):
                        let bound = NavigationStackNode(pathName: stack.pathName, rootName: stack.rootName,
                            enumName: stack.enumName, content: stack.content.compactMap(bind),
                            destinations: stack.destinations, models: stack.models)
                        return .navigationStack(bound, location: location)
                    case .text, .markdown, .navigationLink, .native, .child, .tabView, .image, .toggle,
                         .textInput, .secureInput, .label, .divider, .spacer:
                        return node
                    }
                }
                guard let body = bind(screen.body) else {
                    return Screen(name: screen.name, parameters: screen.parameters, states: screen.states,
                                  modals: screen.modals, navigation: operation, body: screen.body,
                                  nativeValues: screen.nativeValues, lifecycle: screen.lifecycle, location: screen.location)
                }
                return Screen(name: screen.name, parameters: screen.parameters, states: screen.states,
                              modals: screen.modals, navigation: operation, body: body,
                              nativeValues: screen.nativeValues, lifecycle: screen.lifecycle, location: screen.location)
            } else if !screen.states.contains(where: { if case .navigationPath = $0 { true } else { false } }) {
                diagnostics.append(Diagnostic(code: "RFNAV003",
                    message: "A destination NavigationLink must use the enclosing graph's finite enum.",
                    suggestion: "Use `NavigationLink(\"navigation.open\", value: Route.case)` and register that destination in the same source file.",
                    location: screen.location))
            }
            return Screen(name: screen.name, parameters: screen.parameters, states: screen.states, modals: screen.modals,
                          navigation: bindings[screen.name], body: screen.body,
                          nativeValues: screen.nativeValues, lifecycle: screen.lifecycle, location: screen.location)
        }
    }

    private func containsNavigationLink(_ node: ViewNode) -> Bool {
        if case .navigationLink = node { return true }
        return node.children.contains(where: containsNavigationLink)
    }

    private func containsNavigationLinkSyntax(_ node: SyntaxProtocol) -> Bool {
        if let call = node.as(FunctionCallExprSyntax.self),
           call.calledExpression.trimmedDescription == "NavigationLink" { return true }
        return node.children(viewMode: .sourceAccurate).contains(where: containsNavigationLinkSyntax)
    }

    func validateNavigationDeclarations(_ module: Module) {
        for screen in module.screens {
            guard case let .navigationStack(stack, location) = screen.body, stack.rootName == screen.name else { continue }
            if viewDeclarations[stack.rootName + "Destinations"] != nil {
                diagnostics.append(Diagnostic(code: "RFNAV003",
                    message: "Generated destination component `\(stack.rootName)Destinations` conflicts with a source View.",
                    suggestion: "Rename the navigation root or the conflicting source View.", location: location))
            }
            if stack.models.isEmpty, stack.destinations.contains(where: { $0.model != nil }) {
                diagnostics.append(Diagnostic(code: "RFNAV003",
                    message: "A model destination requires the root's declared model input.",
                    suggestion: "Pass the same declared model from the navigation root.", location: location))
            }
        }
    }

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
        guard currentStates.allSatisfy({ state in
            switch state {
            case .model, .navigationPath, .nativeHost: true
            case .state, .binding, .form, .tabSelection: false
            }
        }), currentStates.filter({ if case .navigationPath = $0 { true } else { false } }).count == 1 else {
            error("RFNAV002", "A navigation root accepts only declared model inputs and one destination path.",
                  "Keep local controls and scalar state in a typed child screen; use one `[Route]` @State path", at: projection)
            return nil
        }
        guard let declaration = enums.first(where: { $0.name == path.1 }), declaration.isNavigationDestination,
              declaration.payloadTypes.isEmpty else {
            error("RFNAV002", "Navigation destinations need a local `Hashable` enum without payloads.",
                  "Use `enum Route: Hashable { case detail }` and pass typed data through a destination model", at: projection)
            return nil
        }
        var content: [ViewNode] = []
        var destinations: [NavigationDestination] = []
        pendingNavigationDestinations = []
        for statement in call.trailingClosure!.statements {
            guard let child = viewStatement(statement) else {
                pendingNavigationDestinations = []
                if diagnostics.isEmpty || diagnostics.last?.code.hasPrefix("RFNAV") != true {
                    error("RFNAV001", "NavigationStack accepts supported content with one navigationDestination registration.",
                          "Use VStack { NavigationLink(...) }.navigationDestination(for: Route.self) { route in ... }", at: statement)
                }
                return nil
            }
            content.append(child)
        }
        destinations = pendingNavigationDestinations
        pendingNavigationDestinations = []
        guard content.count == 1, !destinations.isEmpty,
              Set(destinations.map(\.caseName)).count == destinations.count,
              Set(destinations.map(\.caseName)) == Set(declaration.cases) else {
            error("RFNAV003", "Navigation destinations must cover every enum case exactly once.",
                  "Declare one static case and typed destination view for every case of `\(declaration.name)`", at: call)
            return nil
        }
        func validateLinks(_ node: ViewNode) -> Bool {
            if case let .navigationLink(_, _, _, value, _) = node {
                guard declaration.cases.contains(value) else {
                    error("RFNAV003", "A NavigationLink value must be a case of the stack's destination enum.",
                          "Use a static case declared by `\(declaration.name)`", at: call)
                    return false
                }
            }
            return node.children.allSatisfy(validateLinks)
        }
        guard content.allSatisfy(validateLinks) else { return nil }
        return .navigationStack(NavigationStackNode(pathName: pathName, rootName: currentViewName ?? "",
                                                   enumName: declaration.name,
                                                   content: content, destinations: destinations, models: currentModels),
                                location: location(of: call))
    }

    func navigationLink(_ call: FunctionCallExprSyntax) -> ViewNode? {
        let arguments = Array(call.arguments)
        guard arguments.count == 2, arguments[0].label == nil,
              arguments[1].label?.text == "value",
              arguments[1].expression.is(MemberAccessExprSyntax.self),
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else {
            error("RFNAV001", "NavigationLink accepts one localized title and a static `.case` value.",
                  "Use `NavigationLink(\"navigation.open\", value: .detail)` at the root or `value: Route.detail` in a registered destination; dynamic strings and closure destinations are unsupported", at: call)
            return nil
        }
        let title: Expression
        if let key = stringLiteral(arguments[0].expression), LocalizationKey.isCanonical(key) {
            title = Expression(.localizedText(LocalizedText(key: key)), type: .string, location: location(of: call))
        } else {
            error("RFNAV001", "NavigationLink needs a canonical localized title.",
                  "Use `NavigationLink(\"navigation.open\", value: .detail)` with a resource key", at: call)
            return nil
        }
        let valueExpression = arguments[1].expression
        guard let member = valueExpression.as(MemberAccessExprSyntax.self),
              member.declName.argumentNames == nil else { return nil }
        let destination = member.declName.baseName.text
        if let base = member.base {
            guard currentStates.contains(where: { if case .navigationPath = $0 { true } else { false } }) == false,
                  let enumName = base.as(DeclReferenceExprSyntax.self)?.baseName.text,
                  let declaration = enums.first(where: { $0.name == enumName }),
                  declaration.isNavigationDestination, declaration.cases.contains(destination),
                  viewDeclarations[currentViewName ?? ""] != nil else {
                error("RFNAV003", "A destination link needs an explicit case of its graph's finite enum.",
                      "Use `NavigationLink(\"navigation.open\", value: Route.case)` inside a registered destination View", at: valueExpression)
                return nil
            }
            return .navigationLink(title: title, pathName: "path", enumName: enumName,
                                   destination: destination, location: location(of: call))
        }
        guard let path = currentStates.compactMap({ state -> (String, String)? in
            guard case let .navigationPath(name, enumName, _) = state else { return nil }
            return (name, enumName)
        }).first else {
            error("RFNAV003", "A destination link needs an explicit finite enum case, not an inferred or dynamic route.",
                  "Use `NavigationLink(\"navigation.open\", value: Route.case)` in a registered destination View", at: call)
            return nil
        }
        guard let declaration = enums.first(where: { $0.name == path.1 }),
              declaration.cases.contains(destination) else {
            error("RFNAV003", "A NavigationLink value must be a case of the stack's destination enum.",
                  "Use a static case declared by `\(path.1)`", at: valueExpression)
            return nil
        }
        return .navigationLink(title: title, pathName: path.0, enumName: path.1,
                               destination: destination, location: location(of: call))
    }

    func navigationDestination(_ call: FunctionCallExprSyntax, on node: ViewNode) -> ViewNode? {
        guard case let .stack(axis, _, _, _) = node, axis == .vertical else {
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
        guard call.arguments.count == 1, call.arguments.first?.label?.text == "for",
              call.arguments.first?.expression.trimmedDescription == "\(enumName).self",
              let closure = call.trailingClosure, call.additionalTrailingClosures.isEmpty else {
            error("RFNAV001", "Use `navigationDestination(for: Route.self) { route in switch route ... }`.",
                  "Register one finite destination enum and exhaustive typed branches", at: call)
            return nil
        }
        guard let signature = closure.signature,
              let parameters = signature.parameterClause,
              ((parameters.as(ClosureParameterClauseSyntax.self)?.parameters.count == 1 &&
                parameters.as(ClosureParameterClauseSyntax.self)?.parameters.first?.firstName.text == "route") ||
               (parameters.as(ClosureShorthandParameterListSyntax.self)?.count == 1 &&
                parameters.as(ClosureShorthandParameterListSyntax.self)?.first?.name.text == "route")),
              closure.statements.count == 1,
              let switchStatement = closure.statements.first?.item.as(ExpressionStmtSyntax.self)?
                .expression.as(SwitchExprSyntax.self),
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
