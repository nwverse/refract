import RefractIR
import SwiftSyntax

extension Builder {
    /// Resolves the ordinary Swift chain without changing its iOS meaning. The final
    /// support declaration is not parsed as a view modifier and carries no runtime behavior.
    func projectedCollection(_ expression: ExprSyntax) -> (Expression, CollectionProjection?)? {
        guard let member = sourceCollectionMember(expression),
              let collection = modelCollectionDescriptor(ExprSyntax(member))?.0 else {
            if expression.as(FunctionCallExprSyntax.self) != nil { reportInvalidProjection(expression) }
            return nil
        }
        guard expression.as(FunctionCallExprSyntax.self) != nil else { return (collection, nil) }
        guard let projectionCall = expression.as(FunctionCallExprSyntax.self),
              let projectionMember = projectionCall.calledExpression.as(MemberAccessExprSyntax.self),
              projectionMember.declName.baseName.text == "refractProjection",
              projectionMember.declName.argumentNames == nil,
              projectionCall.arguments.count == 1,
              projectionCall.arguments.first?.label?.text == "name",
              projectionCall.trailingClosure == nil,
              let name = projectionCall.arguments.first?.expression.as(StringLiteralExprSyntax.self),
              name.segments.count == 1,
              let segment = name.segments.first?.as(StringSegmentSyntax.self),
              !segment.content.text.isEmpty,
              let sortCall = projectionMember.base?.as(FunctionCallExprSyntax.self),
              let sortMember = sortCall.calledExpression.as(MemberAccessExprSyntax.self),
              sortMember.declName.baseName.text == "sorted",
              sortCall.arguments.isEmpty, sortCall.trailingClosure != nil,
              let filterCall = sortMember.base?.as(FunctionCallExprSyntax.self),
              let filterMember = filterCall.calledExpression.as(MemberAccessExprSyntax.self),
              filterMember.declName.baseName.text == "filter",
              filterCall.arguments.isEmpty, filterCall.trailingClosure != nil,
              filterMember.base?.as(MemberAccessExprSyntax.self) != nil else {
            reportInvalidProjection(expression)
            return nil
        }
        guard let itemType = modelCollectionDescriptor(ExprSyntax(member))?.1 else { return nil }
        guard let filter = categoryFilter(filterCall.trailingClosure!, item: itemType),
              let sort = intSort(sortCall.trailingClosure!, item: itemType) else { return nil }
        return (collection, CollectionProjection(name: segment.content.text,
            categoryProperty: filter.property, categoryEnum: filter.enumName, categoryParameter: filter.parameter,
            sortProperty: sort.property, ascending: sort.ascending))
    }

    func sourceCollectionMember(_ expression: ExprSyntax) -> MemberAccessExprSyntax? {
        if let member = expression.as(MemberAccessExprSyntax.self) { return member }
        var current = expression
        // Only the bounded filter(...).sorted(...).refractProjection(name:) chain may wrap a source.
        for _ in 0..<3 {
            guard let call = current.as(FunctionCallExprSyntax.self),
                  let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                  let base = member.base else { return nil }
            current = base
            if let source = current.as(MemberAccessExprSyntax.self) { return source }
        }
        return nil
    }

    private func categoryFilter(_ closure: ClosureExprSyntax, item: ItemType) -> (property: String, enumName: String, parameter: String)? {
        guard let itemName = closure.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self)?.first?.name.text,
              let expression = closure.statements.only?.item.as(ExprSyntax.self).map(unwrapped) else {
            invalidProjection("The filter must be one typed finite-category expression.", at: closure)
            return nil
        }
        func resetEquality(_ syntax: ExprSyntax) -> String? {
            guard let operation = unwrapped(syntax).as(InfixOperatorExprSyntax.self),
                  operation.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "==" else { return nil }
            for (candidate, value) in [(operation.leftOperand, operation.rightOperand),
                                       (operation.rightOperand, operation.leftOperand)] {
                if let reference = candidate.as(DeclReferenceExprSyntax.self), enumCase(value, named: "all") {
                    return reference.baseName.text
                }
            }
            return nil
        }
        func equality(_ syntax: ExprSyntax) -> (item: MemberAccessExprSyntax, value: ExprSyntax)? {
            let syntax = unwrapped(syntax)
            guard let operation = syntax.as(InfixOperatorExprSyntax.self),
                  operation.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "==" else { return nil }
            for (candidate, value) in [(operation.leftOperand, operation.rightOperand),
                                       (operation.rightOperand, operation.leftOperand)] {
                if let member = candidate.as(MemberAccessExprSyntax.self),
                   member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == itemName {
                    return (member, value)
                }
            }
            return nil
        }
        var comparison: (item: MemberAccessExprSyntax, value: ExprSyntax)?
        var resetParameter: String?
        if let sequence = expression.as(SequenceExprSyntax.self), sequence.elements.count == 7 {
            let elements = Array(sequence.elements)
            func infixEquality(_ lhs: ExprSyntax, _ operatorExpression: ExprSyntax, _ rhs: ExprSyntax) -> ExprSyntax? {
                guard let operation = operatorExpression.as(BinaryOperatorExprSyntax.self),
                      operation.operator.text == "==" else { return nil }
                return ExprSyntax(InfixOperatorExprSyntax(leftOperand: lhs, operator: operation, rightOperand: rhs))
            }
            guard elements[3].as(BinaryOperatorExprSyntax.self)?.operator.text == "||",
                  let lhs = infixEquality(elements[0], elements[1], elements[2]),
                  let rhs = infixEquality(elements[4], elements[5], elements[6]) else {
                invalidProjection("Use `category == .all || item.category == category`.", at: closure)
                return nil
            }
            for operand in [lhs, rhs] {
                if let reset = resetEquality(operand) {
                    resetParameter = reset
                } else {
                    comparison = equality(operand)
                }
            }
        } else if let expression = expression.as(InfixOperatorExprSyntax.self),
           expression.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "||" {
            for operand in [expression.leftOperand, expression.rightOperand] {
                if let reset = resetEquality(operand) {
                    resetParameter = reset
                    continue
                }
                guard let candidate = equality(operand) else {
                    invalidProjection("Use `category == .all || item.category == category`.", at: closure)
                    return nil
                }
                comparison = candidate
            }
        } else {
            comparison = equality(expression)
        }
        guard let match = comparison,
              let category = match.value.as(DeclReferenceExprSyntax.self),
              let parameter = parameters.first(where: { $0.name == category.baseName.text }),
              let enumName = parameter.enumName,
              let property = item.properties.first(where: { $0.name == match.item.declName.baseName.text && $0.enumName == enumName }),
              let declaration = enums.first(where: { $0.name == enumName && $0.payloadTypes.isEmpty }),
              resetParameter == nil || resetParameter == parameter.name && declaration.cases.contains("all") else {
            invalidProjection("The filter needs a matching enum category input and an `.all` reset on that same input.", at: closure)
            return nil
        }
        return (property.name, enumName, parameter.name)
    }

    private func enumCase(_ expression: ExprSyntax, named name: String) -> Bool {
        guard let member = expression.as(MemberAccessExprSyntax.self), member.declName.baseName.text == name else { return false }
        return member.base == nil || member.base?.as(DeclReferenceExprSyntax.self) != nil
    }

    private func unwrapped(_ expression: ExprSyntax) -> ExprSyntax {
        guard let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
              tuple.elements.first?.label == nil, let element = tuple.elements.first?.expression else { return expression }
        return unwrapped(element)
    }

    private func intSort(_ closure: ClosureExprSyntax, item: ItemType) -> (property: String, ascending: Bool)? {
        guard let parameters = closure.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self),
              parameters.count == 2, let lhsName = parameters.first?.name.text,
              let rhsName = parameters.last?.name.text,
              let expression = closure.statements.only?.item.as(ExprSyntax.self).map(unwrapped),
              let sequence = expression.as(SequenceExprSyntax.self), sequence.elements.count == 5 else {
            invalidProjection("Use a two-argument Int sort with an explicit id tie-break.", at: closure)
            return nil
        }
        let outer = Array(sequence.elements)
        guard let tie = unwrapped(outer[4]).as(SequenceExprSyntax.self), tie.elements.count == 7 else {
            invalidProjection("Use a two-argument Int sort with an explicit id tie-break.", at: closure)
            return nil
        }
        let inner = Array(tie.elements)
        func property(_ expression: ExprSyntax, owner: String, name: String? = nil) -> MemberAccessExprSyntax? {
            guard let member = expression.as(MemberAccessExprSyntax.self),
                  member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == owner,
                  name == nil || member.declName.baseName.text == name else { return nil }
            return member
        }
        func operatorNamed(_ expression: ExprSyntax, _ name: String) -> Bool {
            expression.as(BinaryOperatorExprSyntax.self)?.operator.text == name
        }
        guard operatorNamed(outer[3], "||"), operatorNamed(inner[1], "=="),
              operatorNamed(inner[3], "&&"), operatorNamed(inner[5], "<"),
              let direction = outer[1].as(BinaryOperatorExprSyntax.self)?.operator.text,
              ["<", ">"].contains(direction),
              let primaryLHS = property(outer[0], owner: lhsName),
              let primaryRHS = property(outer[2], owner: rhsName),
              primaryLHS.declName.baseName.text == primaryRHS.declName.baseName.text,
              let equalLHS = property(inner[0], owner: lhsName, name: primaryLHS.declName.baseName.text),
              let equalRHS = property(inner[2], owner: rhsName, name: primaryLHS.declName.baseName.text),
              equalLHS.declName.baseName.text == equalRHS.declName.baseName.text,
              property(inner[4], owner: lhsName, name: item.identity.name) != nil,
              property(inner[6], owner: rhsName, name: item.identity.name) != nil,
              item.identity.type == .int,
              let rank = item.properties.first(where: {
                  $0.name == primaryLHS.declName.baseName.text && $0.type == .int && $0.enumName == nil
              }) else {
            invalidProjection("Use `lhs.rank < rhs.rank || (lhs.rank == rhs.rank && lhs.id < rhs.id)` with an Int rank.", at: closure)
            return nil
        }
        return (rank.name, direction == "<")
    }

    private func reportInvalidProjection(_ expression: ExprSyntax) {
        invalidProjection("Only `model.items.filter { ... }.sorted { ... }.refractProjection(name: \"...\")` is supported.", at: expression)
    }

    private func invalidProjection(_ message: String, at syntax: some SyntaxProtocol) {
        error("RFLIST004", message,
              "Use a finite enum category, `.all` reset, Int sort field, and explicit Int id tie-break", at: syntax)
    }
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}
