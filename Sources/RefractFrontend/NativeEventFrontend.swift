import RefractIR
import SwiftSyntax

extension Builder {
    func hasNativeInputs(_ node: StructDeclSyntax) -> Bool {
        node.memberBlock.members.contains { member in
            guard let type = member.decl.as(VariableDeclSyntax.self)?.bindings.first?.typeAnnotation?.type.trimmedDescription else { return false }
            return nativeHosts.contains(where: { $0.name == type }) ||
                NativeValueKind.allCases.contains(where: { $0.typeName == type })
        }
    }

    func nativeSelectors(_ expression: ExprSyntax) -> [(String, NativeValueField)] {
        let visitor = NativeSelectorVisitor(declared: currentNativeValues.map(\.propertyName))
        visitor.walk(expression)
        return visitor.selectors
    }

    func nativeEventBinding(_ call: FunctionCallExprSyntax) -> String? {
        guard call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "refractNativeValue",
              call.arguments.count == 1, call.arguments.first?.label == nil,
              let member = call.arguments.first?.expression.as(MemberAccessExprSyntax.self),
              member.declName.argumentNames == nil,
              let baseName = nativeSelectorBase(member, declared: currentNativeValues.map(\.propertyName)),
              let value = currentNativeValues.first(where: { $0.propertyName == baseName }),
              let field = NativeValueField(rawValue: member.declName.baseName.text),
              field == value.selectedField,
              field == .state || value.kind.hasCorrelation else {
            error("RFHOST005", "`.refractNativeValue` must select the declared input's state, id or revision on the root.",
                  "Select the event state for an exhaustive switch, or its typed correlation field", at: call)
            return nil
        }
        return call.arguments.first?.expression.trimmedDescription
    }

    func nativeEnumType(named name: String) -> String? {
        currentNativeValues.first(where: { $0.propertyName == name && $0.selectedField == .state })?.kind.stateTypeName
    }
}

private func nativeSelectorBase(_ member: MemberAccessExprSyntax, declared: [String]) -> String? {
    if let base = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
       declared.contains(base) { return base }
    if let implicit = member.base?.as(MemberAccessExprSyntax.self), implicit.base == nil,
       declared.contains(implicit.declName.baseName.text) { return implicit.declName.baseName.text }
    return nil
}

private final class NativeSelectorVisitor: SyntaxVisitor {
    let declared: [String]
    var selectors: [(String, NativeValueField)] = []

    init(declared: [String]) {
        self.declared = declared
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "refractNativeValue",
              node.arguments.count == 1, node.arguments.first?.label == nil,
              let member = node.arguments.first?.expression.as(MemberAccessExprSyntax.self),
              let base = nativeSelectorBase(member, declared: declared),
              let field = NativeValueField(rawValue: member.declName.baseName.text) else { return .visitChildren }
        selectors.append((base, field))
        return .visitChildren
    }
}
