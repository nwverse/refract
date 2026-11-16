import RefractIR
import SwiftSyntax

extension Builder {
    func collectEnums(_ tree: SourceFileSyntax) {
        for statement in tree.statements {
            guard let declaration = statement.item.as(EnumDeclSyntax.self) else { continue }
            guard declaration.inheritanceClause == nil, declaration.genericParameterClause == nil,
                  declaration.genericWhereClause == nil else {
                error("RFCTRL006", "Only finite local enums without inheritance or generics can drive native switch branches.",
                      "Declare a no-payload enum without a raw-value type", at: declaration.name)
                continue
            }
            var names: [String] = []
            var valid = true
            for member in declaration.memberBlock.members {
                guard let element = member.decl.as(EnumCaseDeclSyntax.self), element.elements.count == 1,
                      let first = element.elements.first, first.parameterClause == nil, first.rawValue == nil else {
                    error("RFCTRL006", "Enum payloads, grouped cases and raw values are outside the supported switch slice.",
                          "Use one no-payload case per declaration and no raw-value type", at: member)
                    valid = false
                    continue
                }
                guard !names.contains(first.name.text) else {
                    error("RFCTRL006", "An enum case must have a unique native identity.", at: first.name)
                    valid = false
                    continue
                }
                names.append(first.name.text)
            }
            if valid, !names.isEmpty {
                enums.append(EnumDeclaration(name: declaration.name.text, cases: names,
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
        var cases: [SwitchCase] = []
        for switchCase in statement.cases {
            guard let item = switchCase.as(SwitchCaseSyntax.self) else {
                error("RFCTRL005", "This switch case is not a supported enum case.", at: switchCase)
                return nil
            }
            guard item.label.as(SwitchCaseLabelSyntax.self)?.caseItems.count == 1,
                  let pattern = item.label.as(SwitchCaseLabelSyntax.self)?.caseItems.first?.pattern,
                  let name = simpleEnumCase(pattern), declaration.cases.contains(name) else {
                error("RFCTRL005", "Switch supports one no-payload case per branch, with no default, binding or cast.",
                      "List each declared enum case explicitly", at: item.label)
                return nil
            }
            guard seen.insert(name).inserted else {
                error("RFCTRL007", "Switch case `\(name)` is duplicated.",
                      "Emit each enum case exactly once", at: pattern)
                return nil
            }
            guard let children = builderChildren(item.statements) else { return nil }
            cases.append(SwitchCase(name: name, children: children))
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

    private func simpleEnumCase(_ pattern: PatternSyntax) -> String? {
        if let identifier = pattern.as(IdentifierPatternSyntax.self) { return identifier.identifier.text }
        guard let expression = pattern.as(ExpressionPatternSyntax.self),
              let member = expression.expression.as(MemberAccessExprSyntax.self), member.declName.argumentNames == nil,
              member.base == nil else { return nil }
        return member.declName.baseName.text
    }
}
