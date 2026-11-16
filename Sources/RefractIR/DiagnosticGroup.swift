/// Multiple independent diagnostics from one generation pass. Consumers retain structured locations and codes.
public struct DiagnosticGroup: Error, Equatable, Sendable {
    public let diagnostics: [Diagnostic]
    public init(_ diagnostics: [Diagnostic]) {
        self.diagnostics = diagnostics
    }
}
