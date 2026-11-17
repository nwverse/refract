import RefractIR
import SwiftSyntax

extension Builder {
    /// Collect closed native host roles before parsing any screen inputs.
    func collectNativeHosts(_ tree: SourceFileSyntax) {
        for statement in tree.statements {
            guard let declaration = statement.item.as(ProtocolDeclSyntax.self) else { continue }
            let inherited = declaration.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
            let roles = NativeHostCapability.allCases.filter { inherited.contains($0.marker) }
            guard !roles.isEmpty else { continue }
            guard inherited.count == 1, roles.count == 1, let role = roles.first else {
                error("RFHOST001", "A native host must inherit exactly one lifecycle, notification or background-work role.",
                      "Use one of the closed RefractLifecycleHost, RefractNotificationHost or RefractBackgroundWorkHost markers", at: declaration.name)
                continue
            }
            var actions: [ModelAction] = []
            for member in declaration.memberBlock.members {
                guard let function = member.decl.as(FunctionDeclSyntax.self) else {
                    error("RFHOST002", "A native host role declares only its closed synchronous request actions.",
                          "Move state observation, permission, scheduling and delivery into the app-owned implementation", at: member)
                    continue
                }
                let expected = role.parameters
                guard function.name.text == role.actions.first(where: { !actions.map(\.name).contains($0) }),
                      function.attributes.isEmpty, function.modifiers.isEmpty, function.body == nil,
                      function.genericParameterClause == nil, function.genericWhereClause == nil,
                      function.signature.effectSpecifiers == nil, function.signature.returnClause == nil,
                      function.signature.parameterClause.parameters.count == expected.count else {
                    error("RFHOST002", "Native host `\(declaration.name.text)` must declare exactly `\(role.actions.joined(separator: ", "))` in that order.",
                          role == .lifecycle ? "Use foreground() and background(); do not add arbitrary lifecycle closures" : "Use \(role.parameters.map { "\($0.localName): \($0.type == .string ? "String" : "Int")" }.joined(separator: ", ")) for every request action; return no delivery or execution result", at: function)
                    continue
                }
                var parameters: [ModelParameter] = []
                for (parameter, expected) in zip(function.signature.parameterClause.parameters, expected) {
                    let external = parameter.firstName.tokenKind == .wildcard ? nil : parameter.firstName.text
                    guard external == expected.externalName,
                          parameter.secondName?.text == expected.localName || (parameter.secondName == nil && parameter.firstName.text == expected.localName),
                          scalarType(parameter.type.trimmedDescription) == expected.type,
                          parameter.defaultValue == nil, parameter.ellipsis == nil else {
                        error("RFHOST002", "Host request `\(function.name.text)` has a mismatched id, revision or argument label.",
                              "Preserve the exact typed correlation signature; do not use erased or optional request payloads", at: parameter)
                        continue
                    }
                    parameters.append(ModelParameter(externalName: external, localName: expected.localName, type: expected.type))
                }
                actions.append(ModelAction(name: function.name.text, parameters: parameters, location: location(of: function)))
            }
            guard actions.map(\.name) == role.actions, actions.allSatisfy({ $0.parameters == role.parameters }) else {
                error("RFHOST002", "Native host `\(declaration.name.text)` is missing one or more required role actions.",
                      "Declare the complete \(role.actions.joined(separator: ", ")) role with no additional methods", at: declaration)
                continue
            }
            nativeHosts.append(NativeHostContract(name: declaration.name.text, capability: role, actions: actions,
                                                   location: location(of: declaration.name)))
        }
    }

    func nativeHost(_ reference: NativeHostReference, action name: String, arguments: [ActionArgument] = [],
                    at node: some SyntaxProtocol) -> StateAction? {
        guard let contract = nativeHosts.first(where: { $0.name == reference.protocolName }),
              let action = contract.actions.first(where: { $0.name == name }) else {
            error("RFHOST003", "Host `\(reference.propertyName)` has no declared `\(name)` request for its role.",
                  "Call only the typed requests on this lifecycle, notification or background-work host", at: node)
            return nil
        }
        guard arguments.map(\.label) == action.parameters.map(\.externalName),
              zip(arguments, action.parameters).allSatisfy({ $0.value.type == $1.type }) else {
            error("RFHOST003", "Host request `\(name)` must preserve its typed id and revision correlation arguments.",
                  "Use literal request data with the exact declaration labels; delivery is a later typed event", at: node)
            return nil
        }
        return .hostMethod(host: reference.propertyName, capability: reference.capability, name: name, arguments: arguments)
    }

    func nativeHostAction(_ expression: ExprSyntax) -> StateAction? {
        guard let call = expression.as(FunctionCallExprSyntax.self), call.trailingClosure == nil,
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let reference = currentHosts.first(where: { $0.propertyName == base.baseName.text }) else { return nil }
        var arguments: [ActionArgument] = []
        for argument in call.arguments {
            guard let scalar = scalar(argument.expression), scalar.type != nil else {
                error("RFHOST003", "Host request arguments must have statically known scalar types.",
                      "Use a literal or a typed correlation field; do not erase id or revision", at: argument)
                return nil
            }
            arguments.append(ActionArgument(label: argument.label?.text, value: scalar.expression))
        }
        return nativeHost(reference, action: member.declName.baseName.text, arguments: arguments, at: call)
    }

    func nativeScreenInputs(_ node: StructDeclSyntax, states: [StateDeclaration]) -> (values: [NativeValueReference], lifecycle: NativeLifecycle?)? {
        for member in node.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
                  let kind = NativeValueKind.allCases.first(where: {
                      binding.typeAnnotation?.type.trimmedDescription == $0.typeName
                  }) else { continue }
            guard variable.attributes.count == 1,
                  variable.attributes.first?.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "RefractNativeValue" else {
                error("RFHOST004", "Native event `\(kind.typeName)` requires @RefractNativeValue and an explicit selection modifier.",
                      "Use the reserved typed input and select state, id or revision on the root view", at: variable)
                return nil
            }
        }
        var values: [NativeValueReference] = []
        var selectors: [(String, NativeValueField)] = []
        for member in node.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text, name != "body",
                  let kind = NativeValueKind.allCases.first(where: {
                      binding.typeAnnotation?.type.trimmedDescription == $0.typeName
                  }) else { continue }
            guard variable.bindingSpecifier.tokenKind == .keyword(.var), variable.attributes.count == 1,
                  variable.attributes.first?.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "RefractNativeValue",
                  variable.modifiers.isEmpty, binding.initializer == nil, binding.accessorBlock == nil else {
                error("RFHOST004", "Native value `\(name)` must be `@RefractNativeValue var \(name): \(kind.typeName)`.",
                      "Let the native host supply a complete typed event; do not create an optional stream or callback closure", at: variable)
                continue
            }
            values.append(NativeValueReference(propertyName: name, kind: kind, selectedField: .state))
        }
        // Selection parsing needs the declared input list before the final selected view is chosen.
        currentNativeValues = values
        guard let body = node.memberBlock.members.first(where: {
            $0.decl.as(VariableDeclSyntax.self)?.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "body"
        })?.decl.as(VariableDeclSyntax.self), let bodyBinding = body.bindings.first,
              let accessors = bodyBinding.accessorBlock?.accessors, case let .getter(items) = accessors else { return nil }
        for item in items {
            guard let expression = item.item.as(ExprSyntax.self) else { continue }
            selectors += nativeSelectors(expression)
        }
        var selected: [NativeValueReference] = []
        for value in values {
            let matching = selectors.filter { $0.0 == value.propertyName }
            guard matching.count == 1, let field = matching.first?.1,
                  field == .state || value.kind.hasCorrelation else {
                error("RFHOST004", "Native value `\(value.propertyName)` needs one explicit typed selection.",
                      "Use .refractNativeValue(.state), .refractNativeValue(.id), or .refractNativeValue(.revision) on the root", at: node.name)
                continue
            }
            guard !selected.contains(where: { $0.kind == value.kind && $0.selectedField == field }) else {
                error("RFHOST004", "A screen cannot create two independent views of the same native event field.",
                      "Use one selected event value and correlate it with separate inputs where necessary", at: node.name)
                continue
            }
            selected.append(NativeValueReference(propertyName: value.propertyName, kind: value.kind, selectedField: field))
        }
        let hooks = lifecycleMembers(node)
        let lifecycleStates = states.compactMap { state -> NativeHostReference? in
            guard case let .nativeHost(reference, _) = state, reference.capability == .lifecycle else { return nil }
            return reference
        }
        guard hooks.isEmpty || lifecycleStates.count == 1 else {
            error("RFHOST003", "Screen lifecycle hooks require exactly one typed lifecycle host input.",
                  "Use `let lifecycle: YourLifecycleHost` with foreground() and background()", at: node.name)
            return nil
        }
        let lifecycle: NativeLifecycle?
        if hooks.isEmpty {
            lifecycle = nil
        } else {
            guard Set(hooks) == Set(RefractLifecycleHooks.allCases), let host = lifecycleStates.first,
                  let foreground = nativeHost(host, action: "foreground", at: node.name),
                  let background = nativeHost(host, action: "background", at: node.name) else { return nil }
            lifecycle = NativeLifecycle(foreground: foreground, background: background)
        }
        guard validateNativeHostGraph(states: states, values: selected, lifecycle: lifecycle) else { return nil }
        return (selected, lifecycle)
    }

    private func validateNativeHostGraph(states: [StateDeclaration], values: [NativeValueReference], lifecycle: NativeLifecycle?) -> Bool {
        let hosts = states.compactMap { state -> NativeHostReference? in
            guard case let .nativeHost(reference, _) = state else { return nil }
            return reference
        }
        var valid = true
        for host in hosts {
            if lifecycle == nil, host.capability == .lifecycle {
                error("RFHOST003", "A lifecycle host must be bound to the reserved root foreground/background hooks.",
                      "Use `.refractOnAppear` and `.refractOnDisappear`; do not infer scene state from a button", at: hostSyntax(host.propertyName))
                valid = false
            }
            if host.capability != .lifecycle && !values.contains(where: { $0.kind == (host.capability == .notification ? .notificationEvent : .backgroundWorkEvent) }) {
                error("RFHOST004", "A \(host.capability.rawValue) host requires its explicit typed event input.",
                      "Add the matching @RefractNativeValue event and exhaustively render unavailable, stale and terminal states", at: hostSyntax(host.propertyName))
                valid = false
            }
        }
        for value in values where value.kind == .scenePhase {
            if lifecycle == nil {
                error("RFHOST004", "A scene-phase input requires explicit lifecycle host forwarding.",
                      "Forward application/scene transitions from the app-owned lifecycle host", at: hostSyntax(value.propertyName))
                valid = false
            }
        }
        return valid
    }

    private func hostSyntax(_ name: String) -> TokenSyntax {
        guard let node = currentViewName.flatMap({ viewDeclarations[$0] }) else { return viewDeclarations.values.first!.name }
        return node.memberBlock.members.compactMap { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name else { return nil }
            return variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier
        }.first ?? node.name
    }

    /// An ordinary reference cannot become a source of native side effects. Only native state input
    /// fields have a typed correlation representation; event state is reserved for exhaustive switches.
    func nativeValueProperty(_ expression: ExprSyntax) -> TypedExpression? {
        guard let member = expression.as(MemberAccessExprSyntax.self), member.declName.argumentNames == nil,
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let value = currentNativeValues.first(where: { $0.propertyName == base.baseName.text }),
              let field = NativeValueField(rawValue: member.declName.baseName.text) else { return nil }
        guard field == .state || value.kind.hasCorrelation else {
            error("RFHOST005", "This native value does not expose the requested correlation field.",
                  "Use id, revision and state on notification/background events; switch on scenePhase", at: expression)
            return nil
        }
        guard value.selectedField == field || (value.selectedField == .id && field == .revision) else {
            error("RFHOST005", "The native input must use the field selected on the root view.",
                  "Match the .refractNativeValue selection; do not reinterpret state as a scalar", at: expression)
            return nil
        }
        return TypedExpression(Expression(.nativeValueProperty(NativeValueProperty(value: value.propertyName, field: field)), type: field.type,
                                        location: location(of: expression)), field.type)
    }

    func validateNativeEventSwitch(_ enumName: String) -> Bool {
        guard let kind = NativeValueKind.allCases.first(where: { $0.stateTypeName == enumName }) else { return true }
        guard kind != .scenePhase || currentNativeValues.contains(where: { $0.kind == .scenePhase }),
              kind == .scenePhase || currentNativeValues.contains(where: { $0.kind == kind }) else {
            error("RFHOST005", "An event-state switch requires the corresponding @RefractNativeValue screen input.",
                  "Select the event through the reserved .refractNativeValue modifier", at: viewDeclarations[currentViewName ?? ""]?.name ?? viewDeclarations.values.first!.name)
            return false
        }
        return true
    }
}

enum RefractLifecycleHooks: String, CaseIterable {
    case foreground = "refractOnAppear"
    case background = "refractOnDisappear"
}
