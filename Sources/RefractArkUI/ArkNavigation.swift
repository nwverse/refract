import RefractIR
import RefractMapping

extension Generation {
    func checkedNavigationContext(for screen: Screen) throws -> NavigationOperation? {
        if case let .navigationStack(stack, location) = screen.body {
            let operation = NavigationOperation(pathName: stack.pathName, enumName: stack.enumName)
            let paths = screen.states.compactMap { state -> (String, String)? in
                guard case let .navigationPath(name, enumName, _) = state else { return nil }
                return (name, enumName)
            }
            guard stack.rootName == screen.name, screen.navigation == nil,
                  paths.count == 1, paths[0].0 == operation.pathName, paths[0].1 == operation.enumName else {
                throw Diagnostic(code: "RFNAV003",
                    message: "A navigation root must own the enclosing stack's single typed path operation.",
                    suggestion: "Use one declared @State destination array matching NavigationStack(path:).",
                    location: location)
            }
            return operation
        }
        if let navigation = screen.navigation {
            let isRegistered = module.screens.contains { candidate in
                guard case let .navigationStack(stack, _) = candidate.body,
                      candidate.name == stack.rootName else { return false }
                return stack.destinations.contains(where: { $0.viewName == screen.name })
                    && navigation == NavigationOperation(pathName: stack.pathName, enumName: stack.enumName)
            }
            guard isRegistered else {
                throw Diagnostic(code: "RFNAV003",
                    message: "A qualified NavigationLink needs its checked enclosing navigation operation.",
                    suggestion: "Register the qualified NavigationLink destination with the same typed path and enum in its enclosing graph.",
                    location: screen.location)
            }
            return navigation
        }
        func containsLink(_ node: ViewNode) -> Bool {
            if case .navigationLink = node { return true }
            return node.children.contains(where: containsLink)
        }
        guard !containsLink(screen.body) else {
            throw Diagnostic(code: "RFNAV003",
                message: "A qualified NavigationLink needs its checked enclosing navigation operation.",
                suggestion: "Register the qualified NavigationLink destination in its enclosing typed navigation graph.",
                location: screen.location)
        }
        return nil
    }

    func emitNavigationLink(title: Expression, pathName: String, enumName: String, destination: String,
                            location: SourceLocation?, into writer: inout ArkWriter, mapping: Mapping) throws {
        guard module.enums.first(where: { $0.name == enumName })?.cases.contains(destination) == true else {
            throw Diagnostic(code: "RFNAV003", message: "A NavigationLink destination is not in the declared path enum.",
                             suggestion: "Use a static case of the source destination enum", location: location)
        }
        guard let currentNavigation, pathName == currentNavigation.pathName,
              enumName == currentNavigation.enumName else {
            throw Diagnostic(code: "RFNAV003",
                message: "A NavigationLink must match its checked enclosing navigation operation.",
                suggestion: "Register the qualified NavigationLink destination and use its enclosing graph's typed path and enum.",
                location: location)
        }
        let pathName = currentNavigation.pathName
        writer.line("Button(\(try ArkExpression.emit(title, mapping: mapping)))")
        writer.depth += 1
        writer.open(".onClick(() =>")
        writer.line("this.on\(pathName.prefix(1).uppercased())\(pathName.dropFirst())Navigate(\(enumName).\(destination));")
        writer.close(suffix: ")")
        writer.depth -= 1
    }

    func emitNavigationDestinations(_ stack: NavigationStackNode, into writer: inout ArkWriter) throws {
        guard !stack.rootName.isEmpty, !stack.pathName.isEmpty,
              let declaration = module.enums.first(where: { $0.name == stack.enumName }),
              declaration.isNavigationDestination, declaration.payloadTypes.isEmpty,
              Set(stack.destinations.map(\.caseName)) == Set(declaration.cases),
              Set(stack.destinations.map(\.caseName)).count == stack.destinations.count else {
            throw Diagnostic(code: "RFNAV003", message: "A native navigation stack needs exhaustive finite destinations.")
        }
        writer.line()
        writer.line("@ComponentV2")
        writer.open("export struct \(stack.rootName)Destinations")
        writer.line("@Param @Require public var destination: \(stack.enumName)")
        for model in stack.models {
            writer.line("@Param @Require public var \(model.propertyName): \(model.protocolName)")
        }
        let linkedDestinations = stack.destinations.compactMap { destination in
            module.screens.first(where: { $0.name == destination.viewName })?.navigation
        }
        if !linkedDestinations.isEmpty {
            guard linkedDestinations.allSatisfy({ $0 == NavigationOperation(pathName: stack.pathName, enumName: stack.enumName) }) else {
                throw Diagnostic(code: "RFNAV003", message: "Linked destinations must use the host's single typed navigation operation.")
            }
            try emitNavigationOperation(NavigationOperation(pathName: stack.pathName, enumName: stack.enumName), into: &writer)
        } else {
            writer.line()
        }
        writer.open("build()")
        for (index, destination) in stack.destinations.enumerated() {
            let condition = "this.destination === \(stack.enumName).\(destination.caseName)"
            if index == 0 {
                writer.open("if (\(condition))")
            } else {
                writer.closeBranch("else if (\(condition))")
            }
            if let model = destination.model {
                let targetModel = module.screens.first(where: { $0.name == destination.viewName })?.states
                    .compactMap { state -> ModelReference? in
                        guard case let .model(reference, _) = state else { return nil }
                        return reference
                    }.first(where: { $0.propertyName == model.label })
                guard let targetModel, targetModel.protocolName == stack.models.first(where: {
                    $0.propertyName == model.expression
                })?.protocolName else {
                    throw Diagnostic(code: "RFNAV003", message: "A destination model must match its root and target declarations.")
                }
                var arguments = ["\(model.label): this.\(model.expression)"]
                if let targetNavigation = module.screens.first(where: { $0.name == destination.viewName })?.navigation {
                    let hostOperation = NavigationOperation(pathName: stack.pathName, enumName: stack.enumName)
                    guard targetNavigation == hostOperation else {
                        throw Diagnostic(code: "RFNAV003",
                            message: "A destination callback must match its enclosing typed navigation operation.",
                            suggestion: "Use the same source path and finite enum at every destination forwarding site.")
                    }
                    let name = hostOperation.pathName
                    let callback = "on\(name.prefix(1).uppercased())\(name.dropFirst())Navigate"
                    arguments.append("\(callback): this.\(callback)")
                }
                writer.line("\(destination.viewName)({ \(arguments.joined(separator: ", ")) })")
            } else {
                guard module.nativeDeclarations.contains(where: { $0.name == destination.viewName && $0.parameters.isEmpty }) else {
                    throw Diagnostic(code: "RFNAV003", message: "A native destination needs a zero-argument typed declaration.")
                }
                let resolver = InteropResolver(module: module, mapping: mapping)
                let target = try resolver.target(for: NativeComponent(name: destination.viewName),
                                                 platform: .harmonyOS, location: nil)
                writer.line("\(target.symbol)()")
            }
        }
        writer.close()
        writer.close()
        writer.close()
    }
}
