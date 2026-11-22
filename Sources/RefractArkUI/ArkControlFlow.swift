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
            if declaration.payloadTypes.isEmpty {
                writer.open("export enum \(declaration.name)")
                for name in declaration.cases { writer.line("\(name),") }
                writer.close()
                continue
            }
            guard declaration.payloadTypes.count == declaration.cases.count,
                  Set(declaration.payloadTypes.keys) == Set(declaration.cases) else {
                throw Diagnostic(code: "arkui.invalid_enum_declaration",
                                 message: "A payload enum needs a declared scalar payload on every case.",
                                 location: declaration.location)
            }
            for name in declaration.cases {
                guard let type = declaration.payloadTypes[name] else {
                    throw Diagnostic(code: "arkui.invalid_enum_declaration", message: "Missing enum payload type.")
                }
                let className = enumCaseClass(enum: declaration.name, case: name)
                writer.open("export final class \(className)")
                writer.line("readonly value: \(arkScalar(type));")
                writer.line()
                writer.open("constructor(value: \(arkScalar(type)))")
                writer.line("this.value = value;")
                writer.close()
                writer.close()
            }
            writer.line("export type \(declaration.name) = \(declaration.cases.map { enumCaseClass(enum: declaration.name, case: $0) }.joined(separator: " | "));")
        }
    }

    func emitEnumSwitch(subject: Expression, enumName: String, cases: [SwitchCase],
                        into writer: inout ArkWriter, mapping: Mapping, resolver: InteropResolver?,
                        localAliases: Set<String> = []) throws {
        guard let declaration = enums.first(where: { $0.name == enumName }),
              cases.map(\.name).sorted() == declaration.cases.sorted(), Set(cases.map(\.name)).count == cases.count else {
            throw Diagnostic(code: "arkui.non_exhaustive_switch",
                             message: "A native switch must contain each declared enum case exactly once.",
                             suggestion: "Validate enum exhaustiveness in the frontend.")
        }
        let value = try emitLocalExpression(subject, mapping: mapping)
        let eventValue = declaration.kind?.hasCorrelation == true ? "\(value).state" : value
        for (index, branch) in cases.enumerated() {
            guard ArkText.isIdentifier(branch.name), declaration.cases.contains(branch.name) else {
                throw Diagnostic(code: "arkui.invalid_enum_case", message: "Unknown enum case `\(branch.name)`.")
            }
            let className = enumCaseClass(enum: enumName, case: branch.name)
            if declaration.payloadTypes[branch.name] != nil {
                guard let binding = branch.binding, ArkText.isIdentifier(binding),
                      !module.screens.flatMap(\.parameters).contains(where: { $0.name == binding }) else {
                    throw Diagnostic(code: "arkui.invalid_enum_binding", message: "A payload switch needs a typed local binding.")
                }
                let test = "\(eventValue) instanceof \(className)"
                if index == 0 {
                    writer.open("if (\(test))")
                } else {
                    writer.closeBranch("else if (\(test))")
                }
                writer.line("const \(binding) = \(eventValue).value;")
                for child in branch.children {
                    try emit(child, into: &writer, item: binding, mapping: mapping, resolver: resolver,
                             localAliases: localAliases)
                }
                continue
            } else {
                guard branch.binding == nil else {
                    throw Diagnostic(code: "arkui.invalid_enum_binding", message: "A no-payload case cannot bind a value.")
                }
                if index == 0 {
                    writer.open("if (\(eventValue) === \(enumName).\(branch.name))")
                } else {
                    writer.closeBranch("else if (\(eventValue) === \(enumName).\(branch.name))")
                }
            }
            for child in branch.children {
                try emit(child, into: &writer, mapping: mapping, resolver: resolver, localAliases: localAliases)
            }
        }
        writer.close()
    }

    func emitOptionalBinding(subject: Expression, binding: String, children: [ViewNode], otherwise: [ViewNode],
                             location: SourceLocation?, into writer: inout ArkWriter,
                             mapping: Mapping, resolver: InteropResolver?, localAliases: Set<String> = []) throws {
        guard ArkText.isIdentifier(binding), let name = referenceName(subject),
              module.screens.flatMap(\.parameters)
                .contains(where: { $0.name == name && $0.isOptional && $0.enumName == nil }),
              !module.screens.flatMap(\.parameters).contains(where: { $0.name == binding }) else {
            throw Diagnostic(code: "arkui.invalid_optional_binding",
                             message: "Optional binding requires a direct optional scalar screen input.",
                             location: location)
        }
        writer.open("if (this.\(name) !== null && this.\(name) !== undefined)")
        writer.line("const \(binding) = this.\(name);")
        for child in children {
            try emit(child, into: &writer, item: binding, mapping: mapping, resolver: resolver,
                     localAliases: localAliases)
        }
        writer.closeBranch("else")
        for child in otherwise {
            try emit(child, into: &writer, mapping: mapping, resolver: resolver, localAliases: localAliases)
        }
        writer.close()
    }

    private func enumCaseClass(enum name: String, case caseName: String) -> String {
        name + caseName.prefix(1).uppercased() + String(caseName.dropFirst())
    }

    private func arkScalar(_ type: ValueType) -> String {
        switch type {
        case .string: "string"
        case .bool: "boolean"
        case .int, .double: "number"
        case .revision: "bigint"
        }
    }

    private func referenceName(_ expression: Expression) -> String? {
        guard case let .reference(name) = expression.value, ArkText.isIdentifier(name) else { return nil }
        return name
    }
}
