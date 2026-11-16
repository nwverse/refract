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
            out.open("public enum class \(declaration.name)")
            for name in declaration.cases {
                out.line("\(name),")
            }
            out.close()
        }
    }

    func emitEnumSwitch(subject: Expression, enumName: String, cases: [SwitchCase], isRoot: Bool,
                        location: SourceLocation?, into out: inout KotlinWriter, context: inout Context) throws {
        guard let declaration = context.module.enums.first(where: { $0.name == enumName }),
              cases.map(\.name).sorted() == declaration.cases.sorted(), Set(cases.map(\.name)).count == cases.count else {
            throw Diagnostic(code: "RF-C001", message: "A native switch must contain each declared enum case exactly once.",
                             suggestion: "Validate enum exhaustiveness in the frontend.", location: location)
        }
        if isRoot {
            context.imports.insert("androidx.compose.foundation.layout.Box")
            out.open("Box(modifier = modifier)")
        }
        defer { if isRoot { out.close() } }
        out.open("when (\(try renderExpression(subject, context: &context)))")
        for branch in cases {
            guard declaration.cases.contains(branch.name) else {
                throw Diagnostic(code: "RF-C001", message: "Unknown enum case `\(branch.name)`.", location: location)
            }
            out.open("\(enumName).\(branch.name) ->")
            for child in branch.children { try emit(child, into: &out, context: &context) }
            out.close()
        }
        out.close()
    }

    private func invalidConditional(_ location: SourceLocation?) -> Diagnostic {
        Diagnostic(code: "RF-C001",
                   message: "A conditional must start with a condition and have at most one final else branch.",
                   suggestion: "Use if/else if/else with typed Boolean conditions.", location: location)
    }
}
