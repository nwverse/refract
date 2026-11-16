import RefractIR
import RefractMapping

extension Generation {
    func emitEnums(_ declarations: [EnumDeclaration], into writer: inout ArkWriter) throws {
        for declaration in declarations {
            guard ArkText.isIdentifier(declaration.name), !declaration.cases.isEmpty,
                  declaration.cases.allSatisfy(ArkText.isIdentifier) else {
                throw Diagnostic(code: "arkui.invalid_enum_declaration",
                                 message: "An enum used by a view switch needs a valid name and cases.",
                                 location: declaration.location)
            }
            writer.line()
            writer.open("export enum \(declaration.name)")
            for name in declaration.cases { writer.line("\(name),") }
            writer.close()
        }
    }

    func emitEnumSwitch(subject: Expression, enumName: String, cases: [SwitchCase],
                        into writer: inout ArkWriter, mapping: Mapping, resolver: InteropResolver?) throws {
        guard let declaration = module.enums.first(where: { $0.name == enumName }),
              cases.map(\.name).sorted() == declaration.cases.sorted(), Set(cases.map(\.name)).count == cases.count else {
            throw Diagnostic(code: "arkui.non_exhaustive_switch",
                             message: "A native switch must contain each declared enum case exactly once.",
                             suggestion: "Validate enum exhaustiveness in the frontend.")
        }
        let value = try emitLocalExpression(subject, mapping: mapping)
        for (index, branch) in cases.enumerated() {
            guard ArkText.isIdentifier(branch.name), declaration.cases.contains(branch.name) else {
                throw Diagnostic(code: "arkui.invalid_enum_case", message: "Unknown enum case `\(branch.name)`.")
            }
            if index == 0 {
                writer.open("if (\(value) === \(enumName).\(branch.name))")
            } else {
                writer.closeBranch("else if (\(value) === \(enumName).\(branch.name))")
            }
            for child in branch.children {
                try emit(child, into: &writer, mapping: mapping, resolver: resolver)
            }
        }
        writer.close()
    }
}
