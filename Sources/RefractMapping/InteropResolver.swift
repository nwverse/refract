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
        // Both targets are resolved together at their native call sites. Full-module validation happens only for
        // declarations that are not used; used declarations are checked once when each backend emits that call.
        let components = usedComponents()
        let usedNames = Set(components.map(\.node.name))
        for declaration in module.nativeDeclarations where !usedNames.contains(declaration.name) {
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
        return try target(for: declaration, platform: platform, location: location)
    }

    public func nativeComponent(for component: NativeComponent, platform: Platform) -> Component? {
        mapping.platform(platform).nativeComponents[component.name]
    }

    public func imports(for platform: Platform) -> [NativeImport] {
        mapping.platform(platform).imports
    }

    private func usedComponents() -> [(node: NativeComponent, location: SourceLocation?)] {
        var result: [(node: NativeComponent, location: SourceLocation?)] = []
        for screen in module.screens { collect(screen.body, into: &result) }
        return result
    }

    private func collect(_ node: ViewNode,
                         into result: inout [(node: NativeComponent, location: SourceLocation?)]) {
        switch node {
        case let .native(component, location):
            result.append((component, location))
        case let .stack(_, children, _, _), let .layout(_, children, _, _), let .list(children, _, _):
            for child in children { collect(child, into: &result) }
        case let .button(label, _, _, _), let .scroll(_, label, _, _), let .listItem(label, _):
            collect(label, into: &result)
        case let .section(header, children, _):
            _ = header
            for child in children { collect(child, into: &result) }
        case let .forEach(items, _):
            collect(items.content, into: &result)
        case let .conditional(branches, _):
            for branch in branches { for child in branch.children { collect(child, into: &result) } }
        case let .platformView(alternatives, _):
            for child in alternatives.android + alternatives.harmonyOS { collect(child, into: &result) }
        default:
            break
        }
    }

    private func target(for declaration: NativeDeclaration, platform: Platform,
                        location: SourceLocation?) throws -> NativeTarget {
        let component = mapping.platform(platform).nativeComponents[declaration.name]
        let target = component.map { target($0, platform: platform, module: $0.module ?? "") }
        return try InteropMapping.validate(declaration: declaration, target: target,
            platform: platform == .android ? .android : .harmonyOS,
            location: location ?? declaration.location)
    }

    private func targets(for declaration: NativeDeclaration) throws -> (android: NativeTarget, harmonyOS: NativeTarget) {
        let android = mapping.android.nativeComponents[declaration.name].map {
            target($0, platform: .android, module: $0.module ?? "")
        }
        let harmony = mapping.harmonyOS.nativeComponents[declaration.name].map {
            target($0, platform: .harmonyOS, module: $0.module ?? "")
        }
        return try InteropMapping.validate(declaration: declaration, android: android, harmonyOS: harmony,
                                           location: declaration.location)
    }

    private func target(_ component: Component, platform: Platform, module: String) -> NativeTarget {
        NativeTarget(symbol: component.target, module: module,
            kind: component.kind.map { $0 == "component" ? NativeTarget.Kind.component : .composable }
                ?? (platform == .android ? .composable : .component),
            argumentStyle: NativeTarget.ArgumentStyle(rawValue: component.argumentStyle.rawValue) ?? .named,
            parameters: component.parameters.map { parameter in
                NativeTarget.Parameter(label: parameter.label,
                    type: ValueType(rawValue: parameter.type.rawValue) ?? .string,
                    required: parameter.required, targetType: component.targetTypes?[parameter.label])
            },
            arguments: component.arguments.map { NativeTarget.Argument(source: $0.source, target: $0.target) })
    }
}
