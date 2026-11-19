import RefractIR

extension ComposeBackend {
    func emitNativeValueTypes(_ values: [NativeValueReference], into out: inout KotlinWriter,
                              context: inout Context) throws {
        for kind in Set(values.map(\.kind)).sorted(by: { $0.rawValue < $1.rawValue }) where kind.hasCorrelation {
            out.line()
            out.open("public class \(kind.stateTypeName) private constructor(")
            out.line("public val id: String,")
            out.line("public val revision: Int,")
            out.line("public val state: State,")
            out.depth -= 1
            out.line(") {")
            out.depth += 1
            out.open("public enum class State")
            for state in kind.states { out.line("\(state),") }
            out.close()
            out.line()
            out.open("public companion object")
            for state in kind.states {
                out.open("public fun \(state)(id: String, revision: Int): \(kind.stateTypeName)")
                out.line("return \(kind.stateTypeName)(id, revision, State.\(state))")
                out.close()
            }
            out.close()
            out.close()
            out.line()
            out.open("public data class \(kind.correlationTypeName)(")
            out.line("public val id: String,")
            out.line("public val revision: Int,")
            out.depth -= 1
            out.line(")")
        }
    }
}

func emitComposeScenePhase(_ out: inout KotlinWriter) {
    out.line()
    out.open("public enum class RefractScenePhase")
    for state in NativeValueKind.scenePhase.states { out.line("\(state),") }
    out.close()
}
