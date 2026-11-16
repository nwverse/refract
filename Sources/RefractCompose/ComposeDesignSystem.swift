import RefractIR
import RefractMapping

struct ComposeDesignSystem {
    func emit(_ component: ComponentReference, location: SourceLocation?, isRoot: Bool,
              mapping: Mapping, addImport: (String) -> Void) throws -> String {
        let declaration = try mapping.component(named: component.name, platform: .android, location: location)
        let supplied = Dictionary(component.arguments.map { ($0.label, $0) }, uniquingKeysWith: { first, _ in first })
        var arguments: [String] = []
        for binding in declaration.arguments {
            guard let parameter = declaration.parameters.first(where: { $0.label == binding.source }),
                  let argument = supplied[binding.source] else {
                throw Diagnostic(code: "componentArgument", message: "Component `\(component.name)` has an unbound argument.",
                                 suggestion: "Bind every required source argument in refract.json.", location: location)
            }
            let value = try MappedExpression.compose(argument.expression, mapping: mapping, expected: parameter.type)
            if parameter.type == .stringKey {
                addImport("androidx.compose.ui.res.stringResource")
                if let className = mapping.android.resources.className { addImport(className) }
            }
            let text = declaration.argumentStyle == .positional ? value : "\(binding.target ?? parameter.label) = \(value)"
            arguments.append(text)
        }
        var chains: [String] = []
        for modifier in component.modifiers {
            guard let attribute = declaration.attributes[modifier.name],
                  let signature = mapping.android.modifiers[modifier.name] else {
                throw Diagnostic(code: "unsupportedComponentModifier",
                    message: "Modifier `\(modifier.name)` has no Compose lowering for `\(component.name)`.",
                    suggestion: "Declare a typed chain or parameter attribute.", location: modifier.location)
            }
            let values = try modifierValues(modifier, signature: signature, mapping: mapping)
            let rendered = values.enumerated().map { index, value in
                let bindings = attribute.arguments ?? []
                let target = bindings.indices.contains(index) ? bindings[index].target : nil
                return target.map { "\($0) = \(value)" } ?? value
            }
            switch attribute.kind {
            case .parameter:
                let value = try argumentValue(modifier.arguments.first, signature: signature, mapping: mapping)
                arguments.append("\(attribute.target) = \(value)")
            case .chain:
                if attribute.target == "padding" { addImport("androidx.compose.foundation.layout.padding") }
                if attribute.target == "background" { addImport("androidx.compose.foundation.background") }
                if attribute.target == "opacity" { addImport("androidx.compose.ui.draw.alpha") }
                chains.append(".\(attribute.target)(\(rendered.joined(separator: ", ")))")
            }
        }
        if !chains.isEmpty || isRoot {
            let base = isRoot ? "modifier" : "Modifier"
            let chainText = chains.isEmpty ? "" : chains.count == 1 ? chains[0] : "\n" + chains.map { "        \($0)" }.joined(separator: "\n")
            let receiver = declaration.modifierParameter ?? "modifier"
            let modifierArgument = "\(receiver) = \(base)\(chainText)"
            if let index = declaration.parameters.firstIndex(where: { $0.label == receiver }) {
                arguments.insert(modifierArgument, at: min(index, arguments.count))
            } else {
                arguments.append(modifierArgument)
            }
        }
        let opening: String
        switch declaration.argumentStyle {
        case .object:
            throw Diagnostic(code: "componentArgument", message: "Compose cannot use object-style arguments.",
                             suggestion: "Use named or positional Compose arguments.", location: location)
        case .named, .positional:
            if arguments.isEmpty {
                opening = declaration.target + (declaration.hasContent ? "" : "()")
            } else if arguments.count == 1 {
                opening = declaration.target + "(" + arguments[0] + (isRoot ? ",)" : ")")
            } else {
                opening = declaration.target + "(\n" + arguments.map { "    \($0)," }.joined(separator: "\n") + "\n)"
            }
        }
        guard declaration.hasContent else { return opening }
        let content = try component.children.map {
            try emitChild($0, mapping: mapping, addImport: addImport)
        }.joined(separator: "\n").split(separator: "\n").map { "    \($0)" }.joined(separator: "\n")
        if declaration.content == .parameter {
            guard let parameter = declaration.contentParameter else {
                throw Diagnostic(code: "mappingContent", message: "Component `\(component.name)` lacks contentParameter.",
                                 suggestion: "Declare its content parameter.", location: location)
            }
            return declaration.target + "(\n" + arguments.map { "    \($0)," }.joined(separator: "\n")
                + "\n    \(parameter) = {\n" + content + "\n    }\n)"
        }
        return opening + " {\n" + content + "\n}"
    }

    private func argumentValue(_ expression: Expression?, signature: ModifierSignature,
                               mapping: Mapping) throws -> String {
        guard let expression, let parameter = signature.parameters.first else {
            throw Diagnostic(code: "componentArgument", message: "A mapped modifier parameter requires one declared value.",
                             suggestion: "Declare a matching typed signature.", location: expression?.location)
        }
        return try MappedExpression.compose(expression, mapping: mapping, expected: parameter.type)
    }

    private func modifierValues(_ modifier: Modifier, signature: ModifierSignature,
                                mapping: Mapping) throws -> [String] {
        try zip(modifier.arguments, signature.parameters).map {
            try MappedExpression.compose($0.0, mapping: mapping, expected: $0.1.type)
        }
    }

    private func emitChild(_ node: ViewNode, mapping: Mapping, addImport: (String) -> Void) throws -> String {
        switch node {
        case let .component(child, location):
            return try emit(child, location: location, isRoot: false, mapping: mapping, addImport: addImport)
        case let .text(expression, _, _):
            return "Text(\(try MappedExpression.compose(expression, mapping: mapping)))"
        default:
            throw Diagnostic(code: "componentArgument", message: "This child requires the shared backend lowering.",
                             suggestion: "Use a mapped component or supported Text child.", location: nil)
        }
    }
}
