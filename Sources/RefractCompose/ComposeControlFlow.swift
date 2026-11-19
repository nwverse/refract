import RefractIR

extension ComposeBackend {
    /// A native branch preserves source order and evaluates only the selected composable subtree.
    func emitControlFlow(_ branches: [ViewNode.ConditionBranch], isRoot: Bool, location: SourceLocation?,
                         into out: inout KotlinWriter, context: inout Context) throws {
        // A root builder has no single native child that can receive the caller's modifier.
        // Box is the platform container, not an AnyView or a runtime view registry.
        if isRoot {
            context.imports.insert("androidx.compose.foundation.layout.Box")
            out.open("Box(modifier = modifier)")
        }
        defer { if isRoot { out.close() } }
        guard !branches.isEmpty, branches[0].condition != nil else {
            throw invalidConditional(location)
        }
        for (index, branch) in branches.enumerated() {
            if branch.condition == nil, index != branches.count - 1 {
                throw invalidConditional(location)
            }
            if index > 0 { out.depth -= 1 }
            let condition = try branch.condition.map { try renderExpression($0, context: &context) }
            let keyword = index == 0 ? "if" : branch.condition == nil ? "} else" : "} else if"
            out.open(keyword + (condition.map { " (\($0))" } ?? ""))
            for child in branch.children {
                try emit(child, into: &out, context: &context)
            }
        }
        out.close()
    }

    func emitEnumDeclarations(_ declarations: [EnumDeclaration], into out: inout KotlinWriter) throws {
        for declaration in declarations {
            guard !declaration.cases.isEmpty, declaration.name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
                throw Diagnostic(code: "RF-C001", message: "Invalid declared enum identity.", location: declaration.location)
            }
            out.line()
            if declaration.payloadTypes.isEmpty {
                out.open("public enum class \(declaration.name)")
                for name in declaration.cases {
                    out.line("\(name),")
                }
                out.close()
                continue
            }
            guard declaration.payloadTypes.count == declaration.cases.count,
                  Set(declaration.payloadTypes.keys) == Set(declaration.cases) else {
                throw Diagnostic(code: "RF-C001", message: "A payload enum needs a declared scalar payload on every case.",
                                 location: declaration.location)
            }
            out.open("public sealed interface \(declaration.name)")
            for name in declaration.cases {
                guard let type = declaration.payloadTypes[name] else {
                    throw Diagnostic(code: "RF-C001", message: "Missing enum payload type.", location: declaration.location)
                }
                out.line("public data class \(caseClassName(enum: declaration.name, case: name))(")
                out.depth += 1
                out.line("public val value: \(kotlinType(type)),")
                out.depth -= 1
                out.line(") : \(declaration.name)")
            }
            out.close()
        }
    }

    func emitEnumSwitch(subject: Expression, enumName: String, cases: [SwitchCase], isRoot: Bool,
                        location: SourceLocation?, into out: inout KotlinWriter, context: inout Context) throws {
        guard let declaration = context.enums.first(where: { $0.name == enumName }),
              cases.map(\.name).sorted() == declaration.cases.sorted(), Set(cases.map(\.name)).count == cases.count else {
            throw Diagnostic(code: "RF-C001", message: "A native switch must contain each declared enum case exactly once.",
                             suggestion: "Validate enum exhaustiveness in the frontend.", location: location)
        }
        if isRoot {
            context.imports.insert("androidx.compose.foundation.layout.Box")
            out.open("Box(modifier = modifier)")
        }
        defer { if isRoot { out.close() } }
        let renderedSubject = try renderExpression(subject, context: &context)
        let eventSubject = declaration.kind?.hasCorrelation == true ? "\(renderedSubject).state" : renderedSubject
        out.open(declaration.payloadTypes.isEmpty ? "when (\(eventSubject))" : "when (val subject = \(eventSubject))")
        for branch in cases {
            guard declaration.cases.contains(branch.name) else {
                throw Diagnostic(code: "RF-C001", message: "Unknown enum case `\(branch.name)`.", location: location)
            }
            if let payload = declaration.payloadTypes[branch.name] {
                guard let binding = branch.binding, isValidBinding(binding),
                      !context.module.screens.contains(where: { $0.parameters.contains { $0.name == binding } }) else {
                    throw Diagnostic(code: "RF-C001", message: "A payload switch needs a distinct typed local binding.", location: location)
                }
                out.open("is \(enumName).\(caseClassName(enum: enumName, case: branch.name)) ->")
                out.line("val \(binding): \(kotlinType(payload)) = subject.value")
                for child in branch.children { try emit(child, into: &out, context: &context) }
                out.close()
            } else {
                guard branch.binding == nil else {
                    throw Diagnostic(code: "RF-C001", message: "A no-payload case cannot bind a value.", location: location)
                }
                out.open("\(enumName)\(declaration.kind?.hasCorrelation == true ? ".State" : "").\(branch.name) ->")
                for child in branch.children { try emit(child, into: &out, context: &context) }
                out.close()
            }
        }
        out.close()
    }

    private func invalidConditional(_ location: SourceLocation?) -> Diagnostic {
        Diagnostic(code: "RF-C001",
                   message: "A conditional must start with a condition and have at most one final else branch.",
                   suggestion: "Use if/else if/else with typed Boolean conditions.", location: location)
    }

    func emitOptionalBinding(subject: Expression, binding: String, children: [ViewNode], otherwise: [ViewNode],
                             isRoot: Bool, location: SourceLocation?, into out: inout KotlinWriter,
                             context: inout Context) throws {
        guard case let .reference(value) = subject.value, isValidBinding(binding),
              context.module.screens.flatMap(\.parameters)
                .contains(where: { $0.name == value && $0.isOptional && $0.enumName == nil }),
              !context.module.screens.flatMap(\.parameters).contains(where: { $0.name == binding }) else {
            throw Diagnostic(code: "RF-C001", message: "Optional binding requires a declared optional scalar input.",
                             location: location)
        }
        if isRoot {
            context.imports.insert("androidx.compose.foundation.layout.Box")
            out.open("Box(modifier = modifier)")
        }
        defer { if isRoot { out.close() } }
        out.open("if (\(value) != null)")
        out.line("val \(binding) = \(value)")
        for child in children { try emit(child, into: &out, context: &context) }
        out.depth -= 1
        out.open("} else")
        for child in otherwise { try emit(child, into: &out, context: &context) }
        out.close()
    }

    private func caseClassName(enum: String, case name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    private func isValidBinding(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter || first == "_" else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
