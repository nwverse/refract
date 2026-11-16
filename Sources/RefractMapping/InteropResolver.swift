import RefractIR

/// Resolves a source native declaration against both target bindings before any target source is emitted.
public struct InteropResolver: Sendable {
    public let module: Module
    public let mapping: Mapping

    public init(module: Module, mapping: Mapping) {
        self.module = module
        self.mapping = mapping
    }

    public func validate() throws {
        for declaration in module.nativeDeclarations {
            _ = try targets(for: declaration)
        }
    }

    public func target(for component: NativeComponent, platform: Platform,
                       location: SourceLocation? = nil) throws -> NativeTarget {
        guard let declaration = module.nativeDeclarations.first(where: { $0.name == component.name }) else {
            throw Diagnostic(code: "RFNATIVE001",
                message: "Native component `\(component.name)` has no source declaration.",
                suggestion: "Declare `\(component.name): RefractNativeView` with typed stored properties.",
                location: location)
        }
        let targets = try targets(for: declaration, location: location)
        return platform == .android ? targets.android : targets.harmonyOS
    }

    public func imports(for platform: Platform) -> [NativeImport] {
        mapping.platform(platform).imports
    }

    private func targets(for declaration: NativeDeclaration,
                         location: SourceLocation? = nil) throws -> (android: NativeTarget, harmonyOS: NativeTarget) {
        let android = mapping.android.nativeComponents[declaration.name].map {
            target($0, platform: .android, module: $0.module ?? "")
        }
        let harmony = mapping.harmonyOS.nativeComponents[declaration.name].map {
            target($0, platform: .harmonyOS, module: $0.module ?? "")
        }
        return try InteropMapping.validate(declaration: declaration, android: android, harmonyOS: harmony,
                                           location: location ?? declaration.location)
    }

    private func target(_ component: Component, platform: Platform, module: String) -> NativeTarget {
        NativeTarget(symbol: component.target, module: module,
            kind: component.kind == "component" ? .component : .composable,
            argumentStyle: NativeTarget.ArgumentStyle(rawValue: component.argumentStyle.rawValue) ?? .named,
            parameters: component.parameters.map { parameter in
                NativeTarget.Parameter(label: parameter.label,
                    type: ValueType(rawValue: parameter.type.rawValue) ?? .string,
                    required: parameter.required)
            },
            arguments: component.arguments.map { NativeTarget.Argument(source: $0.source, target: $0.target) })
    }
}
