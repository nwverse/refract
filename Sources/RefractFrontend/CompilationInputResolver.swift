import Foundation
import RefractIR
import SwiftParser
import SwiftSyntax

struct CompilationContext {
    let models: [ModelProtocol]
    let itemTypes: [ItemType]
    let allItemTypes: [ItemType]
    let enums: [EnumDeclaration]
    let views: [String: StructDeclSyntax]
    let modelNames: Set<String>
    let ambiguousNames: Set<String>
}

/// A per-invocation declaration table. Only explicitly supplied files participate;
/// no filesystem discovery or process-global state is involved.
struct CompilationInputResolver {
    struct ParsedFile {
        let source: SourceFile
        let tree: SourceFileSyntax
        let parserDiagnostics: [Diagnostic]
        let declarations: [Declaration]
    }

    struct Declaration {
        let name: String
        let file: String
        let location: RefractIR.SourceLocation
        let view: StructDeclSyntax?
    }

    let files: [ParsedFile]
    let declarations: [String: [Declaration]]
    private let modelNames: Set<String>
    private let parsedItems: [String: [ItemType]]
    private let parsedModels: [String: [ModelProtocol]]

    init(sources: [SourceFile]) {
        var files: [ParsedFile] = []
        var declarations: [String: [Declaration]] = [:]
        var modelNames: Set<String> = []
        for source in sources {
            let tree = Parser.parse(source: source.contents)
            let diagnostics = ParserDiagnostics.validate(tree: tree, file: source.path)
            let parsed = Self.declarations(in: tree, source: source)
            files.append(ParsedFile(source: source, tree: tree, parserDiagnostics: diagnostics,
                                    declarations: parsed))
            for declaration in parsed {
                declarations[declaration.name, default: []].append(declaration)
            }
            for statement in tree.statements {
                if let node = statement.item.as(ProtocolDeclSyntax.self),
                   node.inheritanceClause?.inheritedTypes.contains(where: {
                       $0.type.trimmedDescription == "RefractModel"
                   }) == true {
                    modelNames.insert(node.name.text)
                }
            }
        }
        self.files = files
        self.declarations = declarations
        self.modelNames = modelNames
        var parsedItems: [String: [ItemType]] = [:]
        for file in files.sorted(by: { $0.source.path < $1.source.path }) {
            let builder = Builder(file: file.source.path, tree: file.tree, mapping: nil,
                                  collectTopLevelDeclarations: false)
            builder.collectItemTypes(file.tree)
            parsedItems[file.source.path] = builder.itemTypes
        }
        self.parsedItems = parsedItems
        let allItems = files.map { parsedItems[$0.source.path, default: []] }.flatMap { $0 }
        var parsedModels: [String: [ModelProtocol]] = [:]
        for file in files {
            let builder = Builder(file: file.source.path, tree: file.tree, mapping: nil,
                                  compilationContext: CompilationContext(models: [], itemTypes: [], allItemTypes: allItems,
                                                                         enums: [], views: [:],
                                                                         modelNames: modelNames, ambiguousNames: []),
                                  collectTopLevelDeclarations: false)
            parsedModels[file.source.path] = builder.models
        }
        self.parsedModels = parsedModels
    }

    func context(for file: ParsedFile) -> CompilationContext {
        let models = files.filter { $0.source.path != file.source.path }
            .flatMap { parsedModels[$0.source.path, default: []] }
        let items = files.filter { $0.source.path != file.source.path }
            .flatMap { parsedItems[$0.source.path, default: []] }
        let allItems = files.flatMap { parsedItems[$0.source.path, default: []] }
        var enums: [EnumDeclaration] = []
        var views: [String: StructDeclSyntax] = [:]
        var ambiguousNames: Set<String> = []
        // Dependency order is independent of CLI argument order. Declarations in the
        // current file retain their original order and are appended by Builder.
        for candidate in files.sorted(by: { $0.source.path < $1.source.path })
        where candidate.source.path != file.source.path {
            let builder = Builder(file: candidate.source.path, tree: candidate.tree, mapping: nil,
                                  collectTopLevelDeclarations: false)
            builder.collectEnums(candidate.tree)
            enums.append(contentsOf: builder.enums)
            for declaration in candidate.declarations {
                guard let view = declaration.view else { continue }
                views[declaration.name] = view
            }
        }
        for (name, candidates) in declarations where candidates.count > 1 {
            ambiguousNames.insert(name)
        }
        return CompilationContext(models: models, itemTypes: items, allItemTypes: allItems,
                                  enums: enums, views: views,
                                  modelNames: modelNames, ambiguousNames: ambiguousNames)
    }

    func duplicateDiagnostics() -> [String: [Diagnostic]] {
        var result: [String: [Diagnostic]] = [:]
        for (_, candidates) in declarations
        where candidates.count > 1 && Set(candidates.map(\.file)).count > 1 {
            for declaration in candidates {
                let otherFiles = candidates.map(\.file).filter { $0 != declaration.file }
                let locationText = otherFiles.isEmpty ? "the same file" : otherFiles.joined(separator: ", ")
                result[declaration.file, default: []].append(Diagnostic(code: "RFVIEW007",
                    message: "Declaration `\(declaration.name)` is ambiguous because it is declared in \(locationText).",
                    suggestion: "Give every generated View, model, item and enum one unique name in the explicit input set.",
                    location: declaration.location))
            }
        }
        return result
    }

    static func declarationCycleDiagnostic(units: [TranslationUnit]) -> (file: String, diagnostic: Diagnostic)? {
        var edges: [String: [(name: String, location: RefractIR.SourceLocation?)]] = [:]
        var declarations: [String: RefractIR.SourceLocation] = [:]
        for unit in units {
            for screen in unit.module.screens {
                declarations[screen.name] = screen.location
                var found: [(name: String, location: RefractIR.SourceLocation?)] = []
                func collect(_ node: ViewNode) {
                    if case let .child(child, location) = node {
                        found.append((child.name, location))
                    }
                    for child in node.children { collect(child) }
                }
                collect(screen.body)
                edges[screen.name, default: []].append(contentsOf: found)
            }
        }
        var reported: Set<String> = []
        var result: (file: String, diagnostic: Diagnostic)?
        func visit(_ name: String, stack: inout [String], finished: inout Set<String>) {
            if let start = stack.firstIndex(of: name) {
                let cycle = Array(stack[start...]) + [name]
                let key = Set(cycle).sorted().joined(separator: " -> ")
                guard reported.insert(key).inserted else { return }
                let sourceLocation = edges[stack[start]]?.first(where: { $0.name == name })?.location
                    ?? declarations[cycle[0]]
                let diagnostic = Diagnostic(code: "RFVIEW006",
                    message: "Generated child View calls form a recursive cycle: \(cycle.joined(separator: " -> ")).",
                    suggestion: "Break the cycle and pass data through explicit child inputs.", location: sourceLocation)
                result = (sourceLocation?.file ?? "", diagnostic)
                return
            }
            guard !finished.contains(name) else { return }
            stack.append(name)
            for child in edges[name, default: []] {
                visit(child.name, stack: &stack, finished: &finished)
                if result != nil { return }
            }
            stack.removeLast()
            finished.insert(name)
        }
        var finished: Set<String> = []
        for unit in units {
            for screen in unit.module.screens {
                var stack: [String] = []
                visit(screen.name, stack: &stack, finished: &finished)
                if result != nil { break }
            }
            if result != nil { break }
        }
        return result
    }

    private static func declarations(in tree: SourceFileSyntax, source: SourceFile) -> [Declaration] {
        let converter = SourceLocationConverter(fileName: source.path, tree: tree)
        func declaration(_ name: TokenSyntax, view: StructDeclSyntax? = nil) -> Declaration {
            let position = converter.location(for: name.positionAfterSkippingLeadingTrivia)
            return Declaration(name: name.text, file: source.path,
                               location: RefractIR.SourceLocation(file: source.path, line: position.line,
                                                                 column: position.column), view: view)
        }
        return tree.statements.compactMap { statement in
            if let node = statement.item.as(StructDeclSyntax.self) {
                let inherited = node.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
                if inherited.contains("View") || inherited.contains("Identifiable") ||
                    inherited.contains("RefractNativeView") {
                    return declaration(node.name, view: inherited.contains("View") ? node : nil)
                }
            }
            if let node = statement.item.as(ProtocolDeclSyntax.self),
               node.inheritanceClause?.inheritedTypes.contains(where: {
                   $0.type.trimmedDescription == "RefractModel"
               }) == true {
                return declaration(node.name)
            }
            if let node = statement.item.as(EnumDeclSyntax.self) {
                return declaration(node.name)
            }
            return nil
        }
    }
}
