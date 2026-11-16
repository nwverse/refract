import RefractIR

/// Shared target-side interop rendering. Target signatures have already been checked by InteropResolver;
/// unsupported values remain diagnostics rather than empty-string fallbacks.
public enum InteropEmission {
    public static func arguments(for component: NativeComponent, target: NativeTarget,
                          location: SourceLocation? = nil,
                          render: (Expression) throws -> String) throws -> [String] {
        var diagnostics: [Diagnostic] = []
        var values: [String: String] = [:]
        for argument in component.arguments {
            do { values[argument.label] = try render(argument.expression) }
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
