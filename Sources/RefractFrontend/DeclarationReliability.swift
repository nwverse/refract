import RefractIR
import SwiftSyntax

extension Builder {
    /// Ambiguous generated declarations cannot be resolved by first- or last-wins rules.
    /// This pass owns only one source file; cross-file resolution is a separate input boundary.
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
                generated = declaration.inheritanceClause?.inheritedTypes.contains(where: {
                    $0.type.trimmedDescription == "RefractModel"
                }) == true
            } else if let declaration = statement.item.as(EnumDeclSyntax.self) {
                name = declaration.name
                generated = true
            } else {
                continue
            }
            guard generated else { continue }
            if !names.insert(name.text).inserted {
                error("RFSYN004", "Generated declaration `\(name.text)` occurs more than once in this input file.",
                      "Give each generated View, model, item and enum a unique name.", at: name)
            } else {
                names.insert(name.text)
            }
        }
    }

    private func inherits(_ declaration: StructDeclSyntax, anyOf names: [String]) -> Bool {
        declaration.inheritanceClause?.inheritedTypes.contains(where: {
            names.contains($0.type.trimmedDescription)
        }) == true
    }
}
