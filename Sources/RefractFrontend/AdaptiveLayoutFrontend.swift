import RefractIR
import SwiftSyntax

extension Builder {
    func statefulWidthClassScreen(_ node: StructDeclSyntax,
                                  members: MemberBlockItemListSyntax) -> Screen? {
        guard statefulWidthClassInput(node) != nil else { return nil }
        var inputs: [ScreenParameter] = []
        for member in members {
            guard let declaration = member.decl.as(VariableDeclSyntax.self),
                  let binding = declaration.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
                  identifier.text != "body" else { continue }
            if declaration.attributes.contains(where: {
                $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "State" ||
                $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Binding"
            }) { continue }
            guard declaration.bindingSpecifier.tokenKind == .keyword(.let),
                  declaration.attributes.isEmpty, declaration.modifiers.isEmpty,
                  binding.accessorBlock == nil else { continue }
            guard let type = binding.typeAnnotation?.type.trimmedDescription,
                  type == "WidthSizeClass" || models.contains(where: { $0.name == type }) else {
                error("RFADAPT001", "An adaptive settings screen accepts only its model and native width class as immutable inputs.",
                      "Use `let model: YourModel` and `let widthSizeClass: WidthSizeClass`; keep navigation in the host", at: member)
                return nil
            }
            if models.contains(where: { $0.name == type }) { continue }
            inputs.append(ScreenParameter(name: identifier.text, type: .string,
                                              enumName: type == "WidthSizeClass" ? "WidthSizeClass" : nil,
                                              location: location(of: identifier)))
        }
        guard let body = members.first(where: { member in
            member.decl.as(VariableDeclSyntax.self)?.bindings.first?.pattern
                .as(IdentifierPatternSyntax.self)?.identifier.text == "body"
        })?.decl.as(VariableDeclSyntax.self), body.bindings.count == 1,
              let binding = body.bindings.first, let accessors = binding.accessorBlock?.accessors,
              case let .getter(items) = accessors else {
            error("unsupportedViewBody", "An adaptive View must have one expression-bodied body.",
                  "Return `switch widthSizeClass` with compact and expanded alternatives", at: node.name)
            return nil
        }
        guard let states = localStateDeclarations(node) else { return nil }
        let savedStates = currentStates
        let savedModels = currentModels
        let savedParameters = self.parameters
        currentStates = states
        currentModels = states.compactMap { state in
            guard case let .model(reference, _) = state else { return nil }
            return reference
        }
        self.parameters = inputs
        defer {
            currentStates = savedStates
            currentModels = savedModels
            self.parameters = savedParameters
        }
        guard let root = viewStatements(items, body: binding) else { return nil }
        guard case .switchExpression = root else {
            error("RFADAPT001", "A width-class input must drive the View's single `switch widthSizeClass` expression.",
                  "Keep the native alternatives together; do not use width as a scalar or style token", at: body)
            return nil
        }
        return Screen(name: node.name.text, parameters: inputs, states: states, body: root,
                      location: location(of: node.name))
    }

    /// A stateful screen keeps its model, bindings and local state in the existing
    /// frontend; only the native window classification is a typed input.
    func statefulWidthClassInput(_ node: StructDeclSyntax) -> ScreenParameter? {
        let declarations = node.memberBlock.members.compactMap { member -> VariableDeclSyntax? in
            let declaration = member.decl.as(VariableDeclSyntax.self)
            return declaration?.bindings.first?.typeAnnotation?.type.trimmedDescription == "WidthSizeClass" ? declaration : nil
        }
        guard declarations.count == 1, let declaration = declarations.first,
              declaration.bindingSpecifier.tokenKind == .keyword(.let), declaration.attributes.isEmpty,
              declaration.modifiers.isEmpty, declaration.bindings.count == 1,
              let binding = declaration.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
              name.text == "widthSizeClass", binding.initializer == nil, binding.accessorBlock == nil else {
            error("RFADAPT001", "The native width-class input must be one immutable `widthSizeClass` without an initializer.",
                  "Use `let widthSizeClass: WidthSizeClass`; the host owns window measurement", at: node.name)
            return nil
        }
        return ScreenParameter(name: "widthSizeClass", type: .string, enumName: "WidthSizeClass",
                               location: location(of: name))
    }
}
