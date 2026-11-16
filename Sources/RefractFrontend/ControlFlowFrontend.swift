import RefractIR
import SwiftSyntax

/// View-builder control flow is parsed from syntax, not from the spelling of an expression.
extension Builder {
    func view(_ statement: IfExprSyntax) -> ViewNode? {
        var branches: [ViewNode.ConditionBranch] = []
        var current: IfExprSyntax? = statement
        while let node = current {
            guard node.conditions.count == 1, let clause = node.conditions.first else {
                error("RFCTRL001", "A view conditional requires exactly one supported Boolean condition.",
                      "Use a typed model, @State or @Binding Boolean property", at: node.conditions)
                return nil
            }
            let condition: Expression
            switch clause.condition {
            case let .expression(expression):
                guard !containsUnsupportedOptionalOrCast(expression),
                      let value = typedBoolean(expression) else { return nil }
                condition = value
            case .availability, .optionalBinding:
                error("RFCTRL002", "Optional binding and availability conditions are not supported in view conditionals.",
                      "Expose a typed Boolean from the model instead", at: clause.condition)
                return nil
            case .matchingPattern:
                error("RFCTRL005", "Pattern matching is not supported in view conditionals.",
                      "Use a declared Boolean property instead of a matching-pattern condition", at: clause.condition)
                return nil
            }
            guard let children = builderChildren(node.body.statements) else { return nil }
            branches.append(ViewNode.ConditionBranch(condition: condition, children: children))

            guard let otherwise = node.elseBody else { current = nil; continue }
            switch otherwise {
            case let .ifExpr(next):
                current = next
            case let .codeBlock(body):
                guard let children = builderChildren(body.statements) else { return nil }
                branches.append(ViewNode.ConditionBranch(condition: nil, children: children))
                current = nil
            }
        }
        return .conditional(conditions: branches, location: location(of: statement))
    }

    private func typedBoolean(_ expression: ExprSyntax) -> Expression? {
        if let value = expression.as(BooleanLiteralExprSyntax.self) {
            return Expression(.boolLiteral(value.literal.tokenKind == .keyword(.true)), location: location(of: value))
        }
        if let property = modelProperty(expression) {
            guard modelPropertyType(expression) == .bool else {
                error("RFCTRL001", "A view conditional requires a Boolean model property.",
                      "Declare the selected property as Bool in the model protocol", at: expression)
                return nil
            }
            return property
        }
        guard let reference = expression.as(DeclReferenceExprSyntax.self),
              scalarType(named: reference.baseName.text) == .bool else {
            error("RFCTRL001", "The condition `\(expression.trimmedDescription)` is not a supported typed Boolean.",
                  "Use a declared Bool model, @State or @Binding property", at: expression)
            return nil
        }
        for declaration in currentStates {
            switch declaration {
            case let .state(name, _, _, _) where name == reference.baseName.text:
                return Expression(.valueProperty(.state(name)), location: location(of: expression))
            case let .binding(name, _, _) where name == reference.baseName.text:
                return Expression(.valueProperty(.binding(name)), location: location(of: expression))
            default: continue
            }
        }
        return nil
    }

    private func scalarType(named name: String) -> ValueType? {
        for declaration in currentStates {
            switch declaration {
            case let .state(declared, type, _, _) where declared == name:
                return type
            case let .binding(declared, type, _) where declared == name:
                return type
            default: continue
            }
        }
        return nil
    }

    private func modelPropertyType(_ expression: ExprSyntax) -> ValueType? {
        guard let member = expression.as(MemberAccessExprSyntax.self),
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              let reference = currentModels.first(where: { $0.propertyName == base.baseName.text }),
              let model = models.first(where: { $0.name == reference.protocolName }) else { return nil }
        return model.properties.first(where: { $0.name == member.declName.baseName.text })?.type
    }

    private func containsUnsupportedOptionalOrCast(_ expression: ExprSyntax) -> Bool {
        let visitor = UnsupportedConditionVisitor(file: file, converter: converter)
        visitor.walk(expression)
        diagnostics.append(contentsOf: visitor.diagnostics)
        return !visitor.diagnostics.isEmpty
    }

    func builderChildren(_ statements: CodeBlockItemListSyntax) -> [ViewNode]? {
        var children: [ViewNode] = []
        for item in statements {
            guard let child = viewStatement(item) else { return nil }
            children.append(child)
        }
        return children
    }
}

private final class UnsupportedConditionVisitor: SyntaxVisitor {
    let file: String
    let converter: SourceLocationConverter
    var diagnostics: [Diagnostic] = []

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: OptionalChainingExprSyntax) -> SyntaxVisitorContinueKind {
        report(at: node)
        return .skipChildren
    }

    override func visit(_ node: UnresolvedIsExprSyntax) -> SyntaxVisitorContinueKind {
        report(at: node)
        return .skipChildren
    }

    override func visit(_ node: UnresolvedAsExprSyntax) -> SyntaxVisitorContinueKind {
        report(at: node)
        return .skipChildren
    }

    private func report(at node: some SyntaxProtocol) {
        let position = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        diagnostics.append(Diagnostic(code: "RFCTRL004",
                                      message: "Optional chaining, type checks and casts are not supported in view conditions.",
                                      suggestion: "Use a nonoptional declared Boolean property instead",
                                      location: SourceLocation(file: file, line: position.line, column: position.column)))
    }
}
