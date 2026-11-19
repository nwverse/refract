import RefractIR
import SwiftSyntax

extension Builder {
    /// Ambiguous generated declarations cannot be resolved by first- or last-wins rules.
    /// This pass owns only one source file; cross-file resolution is a separate input boundary.
    /// Collect the diagnostic but finish the normal traversal so unrelated source errors are retained.
    /// `Frontend.parse` discards partial IR after that traversal when this marker is present.
    func rejectDuplicateGeneratedDeclarations(_ tree: SourceFileSyntax) {
        var names: Set<String> = []
        for statement in tree.statements {
            let name: TokenSyntax
            let generated: Bool
            if let declaration = statement.item.as(StructDeclSyntax.self) {
                name = declaration.name
                generated = inherits(declaration, anyOf: ["View", "RefractNativeView", "Identifiable"])
            } else if let declaration = statement.item.as(ProtocolDeclSyntax.self) {
                name = declaration.name
                generated = declaration.inheritanceClause?.inheritedTypes.contains(where: { inherited in
                    inherited.type.trimmedDescription == "RefractModel" ||
                        NativeHostCapability.allCases.contains(where: { $0.marker == inherited.type.trimmedDescription })
                }) == true
            } else if let declaration = statement.item.as(EnumDeclSyntax.self) {
                name = declaration.name
                generated = true
            } else {
                continue
            }
            guard generated else { continue }
            if !names.insert(name.text).inserted {
                hasDuplicateGeneratedDeclaration = true
                error("RFSYN004", "Generated declaration `\(name.text)` occurs more than once in this input file.",
                      "Give each generated View, model, item and enum a unique name.", at: name)
            }
        }
    }

    private func inherits(_ declaration: StructDeclSyntax, anyOf names: [String]) -> Bool {
        declaration.inheritanceClause?.inheritedTypes.contains(where: {
            names.contains($0.type.trimmedDescription)
        }) == true
    }
}
