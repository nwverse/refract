import RefractIR

/// Explicit source-file imports are a compile-time dependency edge, not a registry.
/// Grouping by file keeps repeated references to a model and its item deterministic.
enum ArkNativeImports {
    static func emit(module: Module, nativeSource: NativeSource) throws -> [String] {
        var symbols: [String: Set<String>] = [:]
        func reference(_ name: String) throws {
            guard let path = try nativeSource.arkImport(for: name) else { return }
            symbols[path, default: []].insert(name)
        }
        func collect(_ node: ViewNode) throws {
            if case let .child(child, _) = node { try reference(child.name) }
            if case let .forEach(list, _) = node { try reference(list.itemType) }
            for child in node.children(for: .harmonyOS) { try collect(child) }
        }
        for screen in module.screens {
            try collect(screen.body)
            for parameter in screen.parameters {
                if parameter.itemType == "RefractLinkHandoff" { continue }
                if let name = parameter.itemType ?? parameter.enumName { try reference(name) }
            }
            for state in screen.states {
                guard case let .model(model, _) = state else { continue }
                try reference(model.protocolName)
            }
        }
        for model in module.models {
            for property in model.properties {
                if let item = property.collection?.itemType { try reference(item) }
            }
        }
        return symbols.keys.sorted().map { path in
            let names = symbols[path, default: []].sorted().joined(separator: ", ")
            return "import { \(names) } from '\(path)';"
        }
    }
}
