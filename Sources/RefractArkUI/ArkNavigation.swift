import RefractIR
import RefractMapping

extension Generation {
    func emitNavigationLink(title: Expression, pathName: String, enumName: String, destination: String,
                            into writer: inout ArkWriter, mapping: Mapping) throws {
        guard module.enums.first(where: { $0.name == enumName })?.cases.contains(destination) == true else {
            throw Diagnostic(code: "RFNAV003", message: "A NavigationLink destination is not in the declared path enum.",
                             suggestion: "Use a static case of the source destination enum")
        }
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
