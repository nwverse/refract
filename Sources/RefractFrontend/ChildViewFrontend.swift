import RefractIR
import SwiftSyntax

extension Builder {
    func childView(_ call: FunctionCallExprSyntax, declaration: StructDeclSyntax) -> ViewNode? {
        let name = declaration.name.text
        guard call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else {
            error("RFVIEW006", "A generated child View accepts only declared model and item arguments.",
                  "Use the child's typed stored inputs; do not pass a builder closure.", at: call)
            return nil
        }
        var models: [ChildView.Argument] = []
        var item: ChildView.Argument?
        var labels: [String] = []
        for argument in call.arguments {
            guard let label = argument.label?.text, !labels.contains(label) else {
                error("RFVIEW006", "A generated child View argument must have its stored-property label.",
                      "Use `Child(model: model, row: row)` with explicit typed arguments.", at: argument)
                return nil
            }
            labels.append(label)
            if let reference = argument.expression.as(DeclReferenceExprSyntax.self),
               let model = currentModels.first(where: { $0.propertyName == reference.baseName.text }) {
                guard let member = declaration.memberBlock.members.first(where: {
                    $0.decl.as(VariableDeclSyntax.self)?.bindings.first?.pattern
                        .as(IdentifierPatternSyntax.self)?.identifier.text == label
                }), let variable = member.decl.as(VariableDeclSyntax.self),
                   variable.bindingSpecifier.tokenKind == .keyword(.let),
                   variable.attributes.isEmpty,
                   variable.bindings.first?.typeAnnotation?.type.trimmedDescription == model.protocolName else {
                    error("RFVIEW006", "Child model argument `\(label)` does not match the declared model input.",
                          "Match the child View's stored model property name and protocol type.", at: argument)
                    return nil
                }
                models.append(ChildView.Argument(label: label, expression: model.propertyName))
                guard models.count(where: { $0.label == label }) == 1 else {
                    error("RFVIEW006", "A child model input must occur exactly once in declaration order.",
                          "Remove the duplicate model argument.", at: argument)
                    return nil
                }
                continue
            }
            if let reference = argument.expression.as(DeclReferenceExprSyntax.self),
               let currentItem = currentListItem, reference.baseName.text == currentItem,
               let itemType = currentListItemType,
               childItemParameter(declaration, named: label, itemType: itemType.name) {
                guard item == nil else {
                    error("RFVIEW006", "A generated child View accepts one current Identifiable item input.",
                          "Pass the current item once, using the child's declared property label.", at: argument)
                    return nil
                }
                item = ChildView.Argument(label: label, expression: currentItem)
                continue
            }
            error("RFVIEW006", "Child View argument `\(label)` is not a declared model or the current Identifiable item.",
                  "Use only `let model: DeclaredModel` and `let row: IdentifiableItem` stored inputs.", at: argument)
            return nil
        }
        let expected = declaration.memberBlock.members.compactMap { member -> String? in
            guard let binding = member.decl.as(VariableDeclSyntax.self)?.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  identifier != "body" else { return nil }
            return identifier
        }
        guard labels == expected else {
            error("RFVIEW006", "Child View arguments must match every stored input in declaration order.",
                  "Pass each declared model and Identifiable item once, in the child declaration's order.", at: call)
            error("RFVIEW006", "Child View `\(name)` has unsupported or missing stored inputs.",
                  "Pass every declared model and Identifiable item input and no other properties.", at: call)
            return nil
        }
        guard name != currentViewName else {
            error("RFVIEW006", "A generated View cannot call itself recursively.",
                  "Extract a nonrecursive child View with explicit typed inputs.", at: call)
            return nil
        }
        return .child(ChildView(name: name,
                                arguments: call.arguments.compactMap { argument in
                                    guard let label = argument.label?.text else { return nil }
                                    if let model = models.first(where: { $0.label == label }) { return model }
                                    if let item, item.label == label { return item }
                                    return nil
                                }, models: models, item: item), location: location(of: call))
    }

    func validateChildViewGraph(_ module: Module) {
        var edges: [String: [(name: String, location: RefractIR.SourceLocation?)]] = [:]
        for screen in module.screens {
            var found: [(name: String, location: RefractIR.SourceLocation?)] = []
            func visit(_ node: ViewNode) {
                if case let .child(child, location) = node {
                    found.append((child.name, location))
                }
                for child in node.children { visit(child) }
            }
            visit(screen.body)
            edges[screen.name] = found
        }
        var reported: Set<String> = []
        func visit(_ name: String, stack: inout [String]) {
            if let cycleStart = stack.firstIndex(of: name) {
                let cycle = Array(stack[cycleStart...]) + [name]
                let key = Set(cycle).sorted().joined(separator: " -> ")
                guard reported.insert(key).inserted else { return }
                let sourceLocation = edges[stack[cycleStart]]?.first(where: { $0.name == name })?.location
                diagnostics.append(Diagnostic(code: "RFVIEW006",
                    message: "Generated child View calls form a recursive cycle: \(cycle.joined(separator: " -> ")).",
                    suggestion: "Break the cycle and pass data through explicit child inputs.",
                    location: sourceLocation ?? location(of: viewDeclarations[name]?.name ?? viewDeclarations[cycle[0]]!.name)))
                return
            }
            guard let children = edges[name] else { return }
            stack.append(name)
            for child in children { visit(child.name, stack: &stack) }
            stack.removeLast()
        }
        for screen in module.screens {
            var stack: [String] = []
            visit(screen.name, stack: &stack)
        }
    }

    private func childItemParameter(_ declaration: StructDeclSyntax, named name: String,
                                    itemType: String) -> Bool {
        declaration.memberBlock.members.contains { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.bindingSpecifier.tokenKind == .keyword(.let), variable.attributes.isEmpty,
                  let binding = variable.bindings.first,
                  binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name else { return false }
            return binding.typeAnnotation?.type.trimmedDescription == itemType
        }
    }
}
