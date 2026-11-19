import RefractIR

extension Generation {
    func emitArkNativeValueTypes(_ values: [NativeValueReference], into writer: inout ArkWriter) {
        for kind in Set(values.map(\.kind)).sorted(by: { $0.rawValue < $1.rawValue }) {
            writer.line()
            writer.open("export enum \(kind == .scenePhase ? kind.typeName : kind.stateTypeName)")
            for state in kind.states { writer.line("\(state),") }
            writer.close()
            guard kind.hasCorrelation else { continue }
            writer.line()
            writer.open("export interface \(kind.typeName)")
            writer.line("id: string;")
            writer.line("revision: number;")
            writer.line("state: \(kind.stateTypeName);")
            writer.close()
            writer.line()
            writer.open("export interface \(kind.correlationTypeName)")
            writer.line("id: string;")
            writer.line("revision: number;")
            writer.close()
        }
    }
}
