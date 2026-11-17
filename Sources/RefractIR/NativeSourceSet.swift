import Foundation

/// One generated source file and its resolved compile-time sibling declarations.
/// Dependencies are scoped to this invocation; generated code never performs a runtime lookup.
public struct NativeSourceSet: Sendable {
    public let modules: [Module]
    public let models: [ModelProtocol]
    public let itemTypes: [ItemType]
    public let enums: [EnumDeclaration]
    private let screens: [String: String]
    private let items: [String: String]
    private let modelFiles: [String: String]
    private let enumFiles: [String: String]

    public init(modules: [Module]) {
        self.init(modules: modules, models: modules.flatMap(\.models), itemTypes: modules.flatMap(\.itemTypes),
                  enums: modules.flatMap(\.enums))
    }

    public init(modules: [Module], models: [ModelProtocol], itemTypes: [ItemType],
                enums: [EnumDeclaration]? = nil) {
        self.modules = modules
        self.models = Self.uniqueDeclarations(models, name: \.name, location: \.location)
        self.itemTypes = Self.uniqueDeclarations(itemTypes, name: \.name, location: \.location)
        self.enums = Self.uniqueDeclarations(enums ?? modules.flatMap(\.enums), name: \.name, location: \.location)
        var screens: [String: String] = [:]
        var items: [String: String] = [:]
        var models: [String: String] = [:]
        var enums: [String: String] = [:]
        for module in modules {
            for screen in module.screens { screens[screen.name] = module.sourceFile }
            for item in module.itemTypes { items[item.name] = module.sourceFile }
            for model in module.models { models[model.name] = module.sourceFile }
            for enumeration in module.enums { enums[enumeration.name] = module.sourceFile }
        }
        self.screens = screens
        self.items = items
        self.modelFiles = models
        self.enumFiles = enums
    }

    private static func uniqueDeclarations<T>(_ declarations: [T], name: (T) -> String,
                                              location: (T) -> SourceLocation?) -> [T] {
        var keys: Set<String> = []
        return declarations.filter { declaration in
            guard let location = location(declaration) else { return true }
            return keys.insert("\(location.file):\(location.line):\(location.column):\(name(declaration))").inserted
        }
    }

    public func source(for module: Module) throws -> NativeSource {
        guard !module.sourceFile.isEmpty,
              module.sourceFile.split(separator: "/", omittingEmptySubsequences: false).count == 1 else {
            throw Diagnostic(code: "RFVIEW008",
                message: "Cross-file output `\(module.sourceFile)` must be a basename within one flat generated directory.",
                suggestion: "Use sibling input files and preserve their basenames as output filenames.")
        }
        var names: [String: RefractIR.SourceLocation] = [:]
        func collect(_ node: ViewNode) {
            if case let .child(child, location) = node, let location {
                names[child.name] = location
            }
            if case let .forEach(list, _) = node, let location = list.location {
                names[list.itemType] = location
            }
            for child in node.children { collect(child) }
        }
        for screen in module.screens {
            collect(screen.body)
            for parameter in screen.parameters {
                if let name = parameter.itemType ?? parameter.enumName, let location = parameter.location {
                    names[name] = location
                }
            }
            for state in screen.states {
                guard case let .model(reference, location) = state, let location else { continue }
                names[reference.protocolName] = location
            }
        }
        for model in module.models {
            for property in model.properties {
                if let item = property.collection?.itemType, let location = property.location {
                    names[item] = location
                }
            }
        }
        var references: [String: String] = [:]
        for (name, _) in names {
            if let file = screens[name] ?? items[name] ?? modelFiles[name] ?? enumFiles[name],
               file != module.sourceFile {
                references[name] = file
            }
            // Other types belong to the application's existing native boundary or
            // a frontend diagnostic; this import pass does not guess their module.
        }
        return NativeSource(references: references)
    }
}

/// Imports use the CLI's existing flat, one-output-per-input convention. A future
/// directory-preserving output contract must revise this resolver, not guess a path.
public struct NativeSource: Sendable {
    let references: [String: String]

    public func arkImport(for name: String) throws -> String? {
        guard let file = references[name] else { return nil }
        let components = file.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 1, let base = Self.basename(file) else {
            throw Diagnostic(code: "RFVIEW008",
                message: "Cross-file ArkUI import `\(name)` requires flat sibling source and output paths.",
                suggestion: "Supply sibling Swift files with unique basenames and generate all ArkUI outputs into one directory.")
        }
        return "./" + base
    }

    private static func basename(_ file: String) -> String? {
        let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { return nil }
        return name
    }
}
