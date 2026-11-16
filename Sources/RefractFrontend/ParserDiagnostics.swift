import RefractIR
import SwiftDiagnostics
import SwiftParserDiagnostics
import SwiftSyntax

/// Converts parser recovery information into the stable generator diagnostic contract.
/// A recovered tree is never a valid source for native generation.
enum ParserDiagnostics {
    static func validate(tree: SourceFileSyntax, file: String) -> [RefractIR.Diagnostic] {
        guard tree.hasError else { return [] }
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        return ParseDiagnosticsGenerator.diagnostics(for: tree)
            .filter { $0.diagMessage.severity == .error }
            .sorted { lhs, rhs in
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.message < rhs.message
            }
            .map { parserDiagnostic in
                let position = converter.location(for: parserDiagnostic.position)
                return Diagnostic(code: "RFSYN001",
                                  message: "Swift parsing failed: \(parserDiagnostic.message)",
                                  suggestion: "Correct the Swift syntax before generating native sources.",
                                  location: RefractIR.SourceLocation(file: file, line: position.line,
                                                                     column: position.column))
            }
    }
}
