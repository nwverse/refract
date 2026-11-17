import RefractIR

extension ComposeBackend {
    func emitWidthSizeClassSwitch(subject: Expression, cases: [SwitchCase], isRoot: Bool,
                                  into out: inout KotlinWriter, context: inout Context) throws {
        guard case let .reference(name) = subject.value, name == "widthSizeClass",
              cases.map(\.name) == ["compact", "expanded"] else {
            throw Diagnostic(code: "RFADAPT001",
                             message: "A native width-class switch needs the host's widthSizeClass and exactly compact/expanded branches.",
                             suggestion: "Use `let widthSizeClass: WidthSizeClass` and exhaustive source cases")
        }
        context.imports.insert("androidx.compose.material3.windowsizeclass.WindowWidthSizeClass")
        if isRoot {
            context.imports.insert("androidx.compose.foundation.layout.Box")
            out.open("Box(modifier = modifier)")
        }
        defer { if isRoot { out.close() } }
        // Medium is an expanded alternative too: the source promises only two branches.
        out.open("if (widthSizeClass == WindowWidthSizeClass.Compact)")
        for child in cases[0].children { try emit(child, into: &out, context: &context) }
        out.depth -= 1
        out.open("} else")
        for child in cases[1].children { try emit(child, into: &out, context: &context) }
        out.close()
    }
}
