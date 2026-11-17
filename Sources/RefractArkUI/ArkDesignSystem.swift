import RefractIR
import RefractMapping

/// ArkUI object arguments, builder children and direct attribute chains for mapped components.
struct ArkDesignSystem {
    func emit(_ component: ComponentReference, location: SourceLocation?,
              mapping: Mapping, writer: inout ArkWriter) throws {
        let declaration = try mapping.component(named: component.name, platform: .harmonyOS, location: location)
        guard declaration.argumentStyle == .object else {
            throw Diagnostic(code: "componentArgument", message: "ArkUI components require object-style arguments.",
                             suggestion: "Use argumentStyle object for this component.", location: location)
        }
        let supplied = Dictionary(component.arguments.map { ($0.label, $0) }, uniquingKeysWith: { first, _ in first })
        var arguments: [String] = []
        for binding in declaration.arguments {
            guard let parameter = declaration.parameters.first(where: { $0.label == binding.source }),
                  let argument = supplied[binding.source], let target = binding.target,
                  let expression = argument.expression else {
                throw Diagnostic(code: "componentArgument", message: "Component `\(component.name)` has an unbound argument.",
                                 suggestion: "Bind every required source argument in refract.json.", location: location)
            }
            arguments.append("\(target): \(try MappedExpression.arkUI(expression, mapping: mapping, expected: parameter.type))")
        }
        let call = arguments.isEmpty ? declaration.target : "\(declaration.target)({ \(arguments.joined(separator: ", ")) })"
        if declaration.hasContent {
            writer.open(call)
            for child in component.children {
                try emitChild(child, mapping: mapping, writer: &writer)
            }
            writer.close()
            let attributes = try chains(component, declaration: declaration, mapping: mapping)
            for attribute in attributes.split(separator: "\n") {
                writer.line(String(attribute))
            }
        } else {
            writer.line(call)
            let attributes = try chains(component, declaration: declaration, mapping: mapping)
            for attribute in attributes.split(separator: "\n") {
                writer.line("  " + attribute)
            }
        }
    }

    private func chains(_ component: ComponentReference, declaration: Component,
                        mapping: Mapping) throws -> String {
        try component.modifiers.map { modifier in
            guard let attribute = declaration.attributes[modifier.name],
                  let signature = mapping.harmonyOS.modifiers[modifier.name] else {
                throw Diagnostic(code: "unsupportedComponentModifier",
                    message: "Modifier `\(modifier.name)` has no ArkUI lowering for `\(component.name)`.",
                    suggestion: "Declare a typed attribute chain.", location: modifier.location)
            }
            guard attribute.kind == .chain else {
                throw Diagnostic(code: "componentArgument", message: "ArkUI mapped modifiers must use attribute chains.",
                                 suggestion: "Use kind chain with declared argument types.", location: modifier.location)
            }
            let values = try zip(modifier.arguments, signature.parameters).map {
                try MappedExpression.arkUI($0.0, mapping: mapping, expected: $0.1.type)
            }
            return "\n.\(attribute.target)(\(values.joined(separator: ", ")))"
        }.joined()
    }

    private func emitChild(_ node: ViewNode, mapping: Mapping, writer: inout ArkWriter) throws {
        switch node {
        case let .component(child, location):
            try emit(child, location: location, mapping: mapping, writer: &writer)
        case let .text(expression, _, _):
            writer.line("Text(\(try MappedExpression.arkUI(expression, mapping: mapping)))")
        default:
            throw Diagnostic(code: "componentArgument", message: "This child requires the shared backend lowering.",
                             suggestion: "Use a mapped component or supported Text child.", location: nil)
        }
    }
}
