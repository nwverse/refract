import RefractIR
import RefractMapping

extension Generation {
    func emitNavigationLink(title: Expression, destination: String, into writer: inout ArkWriter,
                            mapping: Mapping) throws {
        guard let path = module.screens.flatMap(\.states).compactMap({ state -> (String, String)? in
            guard case let .navigationPath(name, enumName, _) = state else { return nil }
            return (name, enumName)
        }).first, module.enums.first(where: { $0.name == path.1 })?.cases.contains(destination) == true else {
            throw Diagnostic(code: "RFNAV003", message: "A NavigationLink destination is not in the declared path enum.",
                             suggestion: "Use a static case of the source destination enum")
        }
        writer.line("Button(\(try ArkExpression.emit(title, mapping: mapping)))")
        writer.depth += 1
        writer.open(".onClick(() =>")
        writer.line("this.on\(path.0.prefix(1).uppercased())\(path.0.dropFirst())Navigate(\(path.1).\(destination));")
        writer.close(suffix: ")")
        writer.depth -= 1
    }

    func emitNavigationDestinations(_ stack: NavigationStackNode, into writer: inout ArkWriter) throws {
        guard let declaration = module.enums.first(where: { $0.name == stack.enumName }),
              declaration.isNavigationDestination, declaration.payloadTypes.isEmpty,
              Set(stack.destinations.map(\.caseName)) == Set(declaration.cases) else {
            throw Diagnostic(code: "RFNAV003", message: "A native navigation stack needs exhaustive finite destinations.")
        }
        writer.line()
        writer.line("@ComponentV2")
        writer.open("export struct \(stack.rootName)Destinations")
        writer.line("@Param @Require public var destination: \(stack.enumName)")
        for model in stack.models {
            writer.line("@Param @Require public var \(model.propertyName): \(model.protocolName)")
        }
        writer.line()
        writer.open("build()")
        for (index, destination) in stack.destinations.enumerated() {
            let condition = "this.destination === \(stack.enumName).\(destination.caseName)"
            if index == 0 {
                writer.open("if (\(condition))")
            } else {
                writer.closeBranch("else if (\(condition))")
            }
            if let model = destination.model {
                writer.line("\(destination.viewName)({ \(model.label): this.\(model.expression) })")
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
