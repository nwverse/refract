import RefractIR
import RefractMapping
import SwiftSyntax

/// Source-level checks and typed IR construction for mapped design-system views.
/// This extends the existing SwiftSyntax visitor; it is not a second parser.
struct DesignSystemFrontend {
    unowned let builder: Builder
    let mapping: Mapping

    func component(_ call: FunctionCallExprSyntax, name: String) -> ViewNode? {
        if mapping.android.nativeComponents[name] != nil || mapping.harmonyOS.nativeComponents[name] != nil {
            return nil // Native declarations and their source signature remain #7's responsibility.
        }
        guard mapping.android.components[name] != nil || mapping.harmonyOS.components[name] != nil else { return nil }
        do {
            let android = try mapping.component(named: name, platform: .android, location: builder.location(of: call))
            _ = try mapping.component(named: name, platform: .harmonyOS, location: builder.location(of: call))
            guard let arguments = try arguments(call, declaration: android) else { return nil }
            let children: [ViewNode]
            if android.hasContent {
                guard call.trailingClosure != nil else {
                    builder.error("componentArgument", "Component `\(name)` requires a child view builder.",
                                  "Supply its children in the trailing closure.", at: call)
                    return nil
                }
                guard let parsed = builder.children(of: call.trailingClosure) else { return nil }
                children = parsed
            } else {
                guard call.trailingClosure == nil else {
                    builder.error("componentArgument", "Component `\(name)` does not accept children.",
                                  "Remove the trailing closure or map a content-capable native component.", at: call)
                    return nil
                }
                children = []
            }
            let reference = ComponentReference(name: name, arguments: arguments, children: children)
            if let hostModifiers = builder.designSystemModifiers(before: call.trailingClosure) {
                return .component(ComponentReference(name: name, arguments: arguments, children: children,
                    modifiers: hostModifiers), location: builder.location(of: call))
            }
            return .component(reference, location: builder.location(of: call))
        } catch let diagnostic as Diagnostic {
            builder.diagnostics.append(diagnostic)
            return nil
        } catch {
            builder.error("missingComponentMapping", "Component `\(name)` could not be resolved.",
                          "Declare its typed mapping on both platforms.", at: call)
            return nil
        }
    }

    func modifiers(_ modifiers: [Modifier], on component: ComponentReference) -> ViewNode? {
        do {
            let declaration = try mapping.component(named: component.name, platform: .android)
            for modifier in modifiers {
                guard declaration.modifiers.contains(modifier.name), let signature = mapping.android.modifiers[modifier.name] else {
                    throw Diagnostic(code: "unsupportedComponentModifier",
                        message: "Modifier `\(modifier.name)` is not accepted by component `\(component.name)`.",
                        suggestion: "Use a declared component modifier or add its typed mapping on both platforms.",
                        location: modifier.location)
                }
                guard modifier.arguments.count == signature.parameters.count else {
                    throw Diagnostic(code: "componentArgument",
                        message: "Modifier `\(modifier.name)` expects \(signature.parameters.count) arguments, not \(modifier.arguments.count).",
                        suggestion: "Pass the declared modifier values in source order.", location: modifier.location)
                }
            }
            return .component(ComponentReference(name: component.name, arguments: component.arguments,
                                                 children: component.children,
                                                 modifiers: component.modifiers + modifiers), location: nil)
        } catch let diagnostic as Diagnostic {
            builder.diagnostics.append(diagnostic)
            return nil
        } catch { return nil }
    }

    private func arguments(_ call: FunctionCallExprSyntax,
                           declaration: Component) throws -> [NativeArgument]? {
        guard call.additionalTrailingClosures.isEmpty else {
            builder.error("componentArgument", "Component `\(call.calledExpression.trimmedDescription)` supports one trailing child closure.",
                          "Move other values into declared parameters.", at: call)
            return nil
        }
        let provided = Dictionary(call.arguments.compactMap { argument in
            argument.label.map { ($0.text, argument) }
        }, uniquingKeysWith: { first, _ in first })
        if call.arguments.contains(where: { $0.label == nil }) {
            builder.error("componentArgument", "Mapped components require explicit argument labels.",
                          "Use the labels declared in refract.json.", at: call)
            return nil
        }
        var result: [NativeArgument] = []
        for parameter in declaration.parameters {
            guard let argument = provided[parameter.label] else {
                if parameter.required {
                    throw Diagnostic(code: "componentArgument",
                        message: "Component `\(call.calledExpression.trimmedDescription)` requires `\(parameter.label)`.",
                        suggestion: "Pass all required source parameters.", location: builder.location(of: call))
                }
                continue
            }
            guard let value = builder.scalar(argument.expression) else { return nil }
            if parameter.type == .stringKey {
                guard case let .stringLiteral(key) = value.expression.value else {
                    throw Diagnostic(code: "componentArgument",
                        message: "Parameter `\(parameter.label)` requires a localized string key.",
                        suggestion: "Use a string literal containing a declared resource key.", location: builder.location(of: argument))
                }
                _ = try mapping.stringResource(key, platform: .android, location: value.expression.location)
                _ = try mapping.stringResource(key, platform: .harmonyOS, location: value.expression.location)
            }
            result.append(NativeArgument(label: parameter.label, expression: value.expression,
                                         type: value.type, location: builder.location(of: argument)))
        }
        let known = Set(declaration.parameters.map(\.label))
        for argument in call.arguments where !known.contains(argument.label?.text ?? "") {
            throw Diagnostic(code: "componentArgument",
                message: "Component `\(call.calledExpression.trimmedDescription)` has no parameter `\(argument.label?.text ?? "_")`.",
                suggestion: "Use the source parameters declared in refract.json.", location: builder.location(of: argument))
        }
        return result
    }
}
