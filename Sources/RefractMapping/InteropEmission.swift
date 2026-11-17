import RefractIR

/// Shared target-side interop rendering. Target signatures have already been checked by InteropResolver;
/// unsupported values remain diagnostics rather than empty-string fallbacks.
public enum InteropEmission {
    public static func arguments(for component: NativeComponent, target: NativeTarget,
                          location: SourceLocation? = nil,
                          render: (Expression) throws -> String,
                          renderAction: (StateAction) throws -> String) throws -> [String] {
        var diagnostics: [Diagnostic] = []
        var values: [String: String] = [:]
        for argument in component.arguments {
            do {
                if argument.type == .action, let expression = argument.expression {
                    values[argument.label] = try render(expression)
                } else if let expression = argument.expression {
                    values[argument.label] = try render(expression)
                } else if let action = argument.action {
                    values[argument.label] = try renderAction(action)
                } else {
                    throw Diagnostic(code: "RFNATIVE002",
                        message: "Native component `\(component.name)` has no typed value for `\(argument.label)`.",
                        suggestion: "Supply a scalar or a checked native action.", location: argument.location ?? location)
                }
            }
            catch let diagnostic as Diagnostic { diagnostics.append(diagnostic) }
        }
        guard diagnostics.isEmpty else { throw InteropMappingError(diagnostics: diagnostics) }
        return try target.arguments.map { binding in
            guard let value = values[binding.source], let label = binding.target else {
                throw Diagnostic(code: "RFMAP003",
                    message: "Native component `\(component.name)` has no value bound for `\(binding.source)`.",
                    suggestion: "Match the source argument labels to the typed mapping.", location: location)
            }
            switch target.argumentStyle {
            case .named: return "\(label) = \(value)"
            case .object: return "\(label): \(value)"
            case .positional: return value
            }
        }
    }
}
