import RefractIR

/// Resolves a source native declaration against both target bindings before any target source is emitted.
public struct InteropResolver: Sendable {
    public let module: Module
    public let mapping: Mapping

    public init(module: Module, mapping: Mapping) {
        self.module = module
        self.mapping = mapping
    }

    public func target(for component: NativeComponent, platform: Platform,
                       location: SourceLocation? = nil) throws -> NativeTarget {
        guard let declaration = module.nativeDeclarations.first(where: { $0.name == component.name }) else {
            throw Diagnostic(code: "RFNATIVE001",
                message: "Native component `\(component.name)` has no source declaration.",
                suggestion: "Declare `\(component.name): RefractNativeView` with typed stored properties.",
                location: location)
        }
        return try target(for: declaration, platform: platform, location: location)
    }

    public func nativeComponent(for component: NativeComponent, platform: Platform) -> Component? {
        mapping.platform(platform).nativeComponents[component.name]
    }

    public func imports(for platform: Platform) -> [NativeImport] {
        mapping.platform(platform).imports
    }

    private func target(for declaration: NativeDeclaration, platform: Platform,
                        location: SourceLocation?) throws -> NativeTarget {
        let component = mapping.platform(platform).nativeComponents[declaration.name]
        let target = component.map { self.target($0, platform: platform, module: $0.module ?? "") }
        return try InteropMapping.validate(declaration: declaration, target: target,
            platform: platform == .android ? .android : .harmonyOS,
            location: location ?? declaration.location)
    }

    private func target(_ component: Component, platform: Platform, module: String) -> NativeTarget {
        NativeTarget(symbol: component.target, module: module,
            kind: component.kind.map { $0 == "component" ? NativeTarget.Kind.component : .composable }
                ?? (platform == .android ? .composable : .component),
            argumentStyle: NativeTarget.ArgumentStyle(rawValue: component.argumentStyle.rawValue) ?? .named,
            parameters: component.parameters.map { parameter in
                NativeTarget.Parameter(label: parameter.label,
                    type: NativeParameterType(rawValue: parameter.type.rawValue) ?? .string,
                    required: parameter.required, targetType: component.targetTypes?[parameter.label])
            },
            arguments: component.arguments.map { NativeTarget.Argument(source: $0.source, target: $0.target) })
    }
}
