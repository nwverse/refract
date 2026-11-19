import RefractIR

extension Generation {
    func emitArkNativeHosts(_ hosts: [NativeHostContract], into writer: inout ArkWriter) throws {
        for host in hosts {
            guard ArkText.isIdentifier(host.name), host.actions.map(\.name) == host.capability.actions,
                  host.actions.allSatisfy({ $0.parameters == host.capability.parameters }) else {
                throw Diagnostic(code: "RFHOST002", message: "Native host `\(host.name)` does not match its closed capability signature.",
                                 suggestion: "Use the exact lifecycle or correlated request role.", location: host.location)
            }
            writer.line()
            writer.open("export interface \(host.name)")
            for action in host.actions {
                let parameters = action.parameters.map { parameter in
                    let type = parameter.type == .string ? "string" : "number"
                    return "\(parameter.localName): \(type)"
                }.joined(separator: ", ")
                writer.line("\(action.name)(\(parameters)): void;")
            }
            writer.close()
        }
    }

    func emitArkNativeValues(_ values: [NativeValueReference], into writer: inout ArkWriter) {
        for value in values {
            if value.selectedField != .state {
                writer.line("@Require @Param \(value.propertyName): \(value.kind.correlationTypeName);")
            } else {
                writer.line("@Require @Param \(value.propertyName): \(value.kind.stateTypeName);")
            }
        }
    }

    func emitArkLifecycle(_ lifecycle: NativeLifecycle?, into writer: inout ArkWriter) throws {
        guard let lifecycle else { return }
        writer.line()
        writer.open("aboutToAppear()")
        writer.line(try emitLocalAction(lifecycle.foreground))
        writer.close()
        writer.line()
        writer.open("aboutToDisappear()")
        writer.line(try emitLocalAction(lifecycle.background))
        writer.close()
        writer.line()
    }
}

func emitArkNativeHostAction(host: String, capability: NativeHostCapability, name: String,
                             arguments: [ActionArgument]) throws -> String {
    guard capability.actions.contains(name), arguments.map(\.label) == capability.parameters.map(\.externalName),
          zip(arguments, capability.parameters).allSatisfy({ $0.value.type == $1.type }) else {
        throw Diagnostic(code: "RFHOST003", message: "The host request no longer matches its checked capability signature.",
                         suggestion: "Keep id and revision typed; do not return or infer a scheduling result.")
    }
    return "this.\(host).\(name)(\(try arguments.map { try emitLocalExpression($0.value) }.joined(separator: ", ")));"
}
