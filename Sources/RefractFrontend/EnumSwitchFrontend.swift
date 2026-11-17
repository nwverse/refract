import RefractIR
import SwiftSyntax

extension Builder {
    func collectEnums(_ tree: SourceFileSyntax) {
        for statement in tree.statements {
            guard let declaration = statement.item.as(EnumDeclSyntax.self) else { continue }
            let inherited = declaration.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
            guard inherited == [] || inherited == ["Hashable"], declaration.genericParameterClause == nil,
                  declaration.genericWhereClause == nil else {
                error("RFCTRL006", "Only finite local enums without inheritance or generics can drive native switch branches.",
                      "Declare a no-payload enum without a raw-value type", at: declaration.name)
                continue
            }
            var names: [String] = []
            var payloads: [String: ValueType] = [:]
            var valid = true
            for member in declaration.memberBlock.members {
                guard let element = member.decl.as(EnumCaseDeclSyntax.self), element.elements.count == 1,
                      let first = element.elements.first, first.rawValue == nil else {
                    error("RFCTRL006", "Grouped cases and raw values are outside the typed switch slice.",
                          "Declare one enum case per statement without a raw value", at: member)
                    valid = false
                    continue
                }
                if let clause = first.parameterClause {
                    guard clause.parameters.count == 1, let parameter = clause.parameters.first,
                          parameter.firstName == nil, parameter.secondName == nil, parameter.defaultValue == nil,
                          let type = scalarType(parameter.type.trimmedDescription) else {
                        error("RFCTRL006", "Each payload case needs exactly one unlabeled String, Int, Double or Bool value.",
                              "Use `case value(String)` without labels, defaults, generics or reference payloads", at: clause)
                        valid = false
                        continue
                    }
                    payloads[first.name.text] = type
                }
                guard !names.contains(first.name.text) else {
                    error("RFCTRL006", "An enum case must have a unique native identity.", at: first.name)
                    valid = false
                    continue
                }
                names.append(first.name.text)
            }
            if !payloads.isEmpty, payloads.count != names.count {
                error("RFCTRL006", "Payload enums must have one scalar payload on every case in this slice.",
                      "Use a separate no-payload enum or add a scalar payload to each case", at: declaration.name)
                valid = false
            }
            if valid, !names.isEmpty, inherited == ["Hashable"], !payloads.isEmpty {
                error("RFNAV002", "A navigation destination enum cannot carry payload objects.",
                      "Use no-payload Hashable cases and pass a declared typed model to the destination View", at: declaration.name)
                valid = false
            }
            if valid, !names.isEmpty {
                enums.append(EnumDeclaration(name: declaration.name.text, cases: names, payloadTypes: payloads,
                                             isNavigationDestination: inherited == ["Hashable"],
                                             location: location(of: declaration.name)))
            } else if valid {
                error("RFCTRL006", "A switch-driving enum must declare at least one case.", at: declaration.name)
            }
        }
    }

    func view(_ statement: SwitchExprSyntax) -> ViewNode? {
        guard let subject = statement.subject.as(DeclReferenceExprSyntax.self),
              let enumName = enumType(named: subject.baseName.text),
              let declaration = enums.first(where: { $0.name == enumName }) else {
            error("RFCTRL003", "Switch requires a declared enum-typed immutable screen input.",
                  "Use `let value: YourEnum` with a local no-payload enum declaration", at: statement.subject)
            return nil
        }
        var seen: Set<String> = []
        var boundNames: Set<String> = []
        var cases: [SwitchCase] = []
        for switchCase in statement.cases {
            guard let item = switchCase.as(SwitchCaseSyntax.self) else {
                error("RFCTRL005", "This switch case is not a supported enum case.", at: switchCase)
                return nil
            }
            guard let label = item.label.as(SwitchCaseLabelSyntax.self), label.caseItems.count == 1,
                  let pattern = label.caseItems.first?.pattern else {
                error("RFCTRL005", "Use exactly one declared enum case per switch branch without default or where clauses.",
                      "List every declared case explicitly", at: item.label)
                return nil
            }
            let parsed = enumCasePattern(pattern, declaration: declaration)
            guard let parsed, seen.insert(parsed.name).inserted else {
                if let parsed {
                    error("RFCTRL007", "Switch case `\(parsed.name)` is duplicated.",
                          "Emit each enum case exactly once", at: pattern)
                } else {
                    error("RFCTRL005", "Switch requires a declared case and a matching optional scalar payload binding.",
                          "Bind exactly one scalar as `case .value(let text)`; no default, cast or where clause", at: pattern)
                }
                return nil
            }
            if let binding = parsed.binding {
                guard !parameters.contains(where: { $0.name == binding }), boundNames.insert(binding).inserted else {
                    error("RFCTRL005", "Payload binding `\(binding)` shadows another input or binding.",
                          "Use a distinct local name in each case", at: pattern)
                    return nil
                }
                currentBindings[binding] = declaration.payloadTypes[parsed.name]
            }
            guard let children = builderChildren(item.statements) else {
                if let binding = parsed.binding { currentBindings.removeValue(forKey: binding) }
                return nil
            }
            if let binding = parsed.binding { currentBindings.removeValue(forKey: binding) }
            cases.append(SwitchCase(name: parsed.name, binding: parsed.binding, children: children))
        }
        let missing = declaration.cases.filter { !seen.contains($0) }
        guard missing.isEmpty else {
            error("RFCTRL007", "Switch over `\(enumName)` is not exhaustive; missing \(missing.joined(separator: ", ")).",
                  "Add every declared case instead of a default branch", at: statement.cases)
            return nil
        }
        let source = Expression(.reference(subject.baseName.text), location: location(of: subject))
        return .switchExpression(subject: source, enumName: enumName, cases: cases, location: location(of: statement))
    }

    private func enumType(named name: String) -> String? {
        parameters.first(where: { $0.name == name })?.enumName
    }

    private func enumCasePattern(_ pattern: PatternSyntax,
                                 declaration: EnumDeclaration) -> (name: String, binding: String?)? {
        guard let expression = pattern.as(ExpressionPatternSyntax.self) else { return nil }
        if let member = expression.expression.as(MemberAccessExprSyntax.self),
           member.base == nil, member.declName.argumentNames == nil {
            let name = member.declName.baseName.text
            guard declaration.cases.contains(name), declaration.payloadTypes[name] == nil else { return nil }
            return (name, nil)
        }
        guard let call = expression.expression.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.base == nil, member.declName.argumentNames == nil,
              declaration.cases.contains(member.declName.baseName.text),
              declaration.payloadTypes[member.declName.baseName.text] != nil,
              call.arguments.count == 1, let argument = call.arguments.first,
              argument.label == nil, call.trailingClosure == nil,
              let wrapped = argument.expression.as(PatternExprSyntax.self),
              let binding = wrapped.pattern.as(ValueBindingPatternSyntax.self),
              binding.bindingSpecifier.tokenKind == .keyword(.let),
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { return nil }
        return (member.declName.baseName.text, identifier.identifier.text)
    }
}
