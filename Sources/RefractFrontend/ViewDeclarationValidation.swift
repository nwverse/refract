import SwiftSyntax

extension Builder {
    /// Reject declarations that would otherwise disappear while the frontend recognizes a sibling body.
    /// The specialized state/model/localization parsers retain ownership of their supported property forms
    /// and their more specific diagnostics.
    func validateViewMembers(_ node: StructDeclSyntax) -> Bool {
        var valid = true
        for member in node.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                error("RFSYN004",
                      "Declaration `\(member.decl.trimmedDescription)` is not supported inside a generated View.",
                      "Move methods, initializers and nested types into the model protocol or a native component.",
                      at: member)
                valid = false
                continue
            }
            guard variable.bindings.count == 1, let binding = variable.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
                  identifier.text != "body", binding.accessorBlock != nil else { continue }
            error("RFSYN004",
                  "Computed property or property observer `\(identifier.text)` is not supported inside a generated View.",
                  "Use a stored typed input or move logic into the model protocol or a native component.",
                  at: member)
            valid = false
        }
        return valid
    }
}
