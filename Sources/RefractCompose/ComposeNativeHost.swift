import RefractIR

extension ComposeBackend {
    /// Closed app-owned capabilities. The generated signatures never include notification managers,
    /// permission results, schedulers, work handles or a target-language implementation template.
    func emitNativeHosts(_ hosts: [NativeHostContract], into out: inout KotlinWriter) throws {
        for host in hosts {
            guard host.actions.map(\.name) == host.capability.actions,
                  host.actions.allSatisfy({ $0.parameters == host.capability.parameters }) else {
                throw Diagnostic(code: "RFHOST002", message: "Native host `\(host.name)` does not match its closed capability signature.",
                                 suggestion: "Validate the complete role before generating either backend.", location: host.location)
            }
            out.line()
            out.open("public interface \(host.name)")
            for action in host.actions {
                let parameters = action.parameters.map {
                    "\($0.localName): \(kotlinType($0.type))"
                }.joined(separator: ", ")
                out.line("public fun \(action.name)(\(parameters))")
            }
            out.close()
        }
    }

    func nativeHostParameters(_ screen: Screen) -> [String] {
        screen.states.compactMap { state in
            guard case let .nativeHost(reference, _) = state else { return nil }
            return "\(reference.propertyName): \(reference.protocolName)"
        }
    }

    func nativeValueParameters(_ values: [NativeValueReference]) -> [String] {
        values.map { value in
            if value.selectedField != .state {
                return "\(value.propertyName): \(value.kind.correlationTypeName)"
            }
            return "\(value.propertyName): \(value.kind.stateTypeName)"
        }
    }

    func emitNativeLifecycle(_ lifecycle: NativeLifecycle?, into out: inout KotlinWriter,
                             context: inout Context) throws {
        guard let lifecycle else { return }
        context.imports.insert("androidx.compose.runtime.DisposableEffect")
        out.open("DisposableEffect(Unit)")
        out.line(try renderAction(lifecycle.foreground, context: &context))
        out.open("onDispose")
        out.line(try renderAction(lifecycle.background, context: &context))
        out.close()
        out.close()
        out.line()
    }

    func renderNativeHostAction(host: String, capability: NativeHostCapability, name: String,
                                arguments: [ActionArgument]) throws -> String {
        guard capability.actions.contains(name), arguments.map(\.label) == capability.parameters.map(\.externalName),
              zip(arguments, capability.parameters).allSatisfy({ $0.value.type == $1.type }) else {
            throw Diagnostic(code: "RFHOST003", message: "The host request no longer matches its checked capability signature.",
                             suggestion: "Keep id and revision typed; do not return or infer a scheduling result.")
        }
        return "\(host).\(name)(\(arguments.map(\.value).map(renderNativeArgument).joined(separator: ", ")))"
    }

    private func renderNativeArgument(_ expression: Expression) -> String {
        switch expression.value {
        case let .stringLiteral(value): "\"\(value.escapedForKotlin())\""
        case let .verbatimText(value): "\"\(value.escapedForKotlin())\""
        case let .boolLiteral(value): value ? "true" : "false"
        case let .numberLiteral(value): value
        case let .nativeValueProperty(value): "\(value.value).\(value.field.rawValue)"
        default: "invalid"
        }
    }
}
