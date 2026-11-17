import RefractIR
import RefractMapping

extension ComposeBackend {
    func emitNavigationStack(_ stack: NavigationStackNode, isRoot: Bool, location: SourceLocation?,
                             into out: inout KotlinWriter, context: inout Context) throws {
        guard isRoot, !stack.rootName.isEmpty, !stack.pathName.isEmpty,
              let declaration = context.module.enums.first(where: { $0.name == stack.enumName }),
              declaration.isNavigationDestination, declaration.payloadTypes.isEmpty,
              Set(stack.destinations.map(\.caseName)) == Set(declaration.cases),
              Set(stack.destinations.map(\.caseName)).count == stack.destinations.count else {
            throw Diagnostic(code: "RFNAV003", message: "A native navigation stack needs exhaustive finite destinations.",
                             suggestion: "Validate the same-file Hashable destination enum in the frontend", location: location)
        }
        // The source NavigationStack is a host boundary, not a second native NavHost. Its root content
        // is emitted as an ordinary component and its destination registrations become a typed switch below.
        for child in stack.content {
            try emit(child, isRoot: true, into: &out, context: &context)
        }
    }

    func emitNavigationLink(title: Expression, pathName: String, enumName: String, destination: String,
                            location: SourceLocation?, into out: inout KotlinWriter,
                            context: inout Context) throws {
        guard context.module.enums.first(where: { $0.name == enumName })?.cases.contains(destination) == true else {
            throw Diagnostic(code: "RFNAV003", message: "A NavigationLink destination is not in the declared path enum.",
                             suggestion: "Use a static case of the source destination enum", location: location)
        }
        context.imports.insert("androidx.compose.material3.Button")
        out.open("Button(onClick = { on\(pathName.uppercasingFirst())Navigate(\(enumName).\(destination)) }, modifier = Modifier)")
        try emit(.text(title, modifiers: [], location: location), into: &out, context: &context)
        out.close()
    }

    func emitNavigationDestinations(_ stack: NavigationStackNode, into out: inout KotlinWriter,
                                    context: inout Context) throws {
        out.line()
        out.line("@Composable")
        out.line("public fun \(stack.rootName)Destinations(")
        out.depth += 1
        out.line("destination: \(stack.enumName),")
        for model in stack.models {
            out.line("\(model.propertyName): \(model.protocolName),")
        }
        out.line("modifier: Modifier = Modifier,")
        out.depth -= 1
        out.line(") {")
        out.depth += 1
        out.open("when (destination)")
        for destination in stack.destinations {
            guard let model = destination.model else {
                guard context.module.nativeDeclarations.contains(where: {
                    $0.name == destination.viewName && $0.parameters.isEmpty
                }) else {
                    throw Diagnostic(code: "RFNAV003", message: "A native destination needs a zero-argument declaration.")
                }
                out.open("\(stack.enumName).\(destination.caseName) ->")
                try emitNative(NativeComponent(name: destination.viewName), location: nil, isRoot: false,
                               into: &out, context: &context)
                out.close()
                continue
            }
            let targetModel = context.module.screens.first(where: { $0.name == destination.viewName })?.states
                .compactMap { state -> ModelReference? in
                    guard case let .model(reference, _) = state else { return nil }
                    return reference
                }.first(where: { $0.propertyName == model.label })
            guard let targetModel, targetModel.protocolName == stack.models.first(where: {
                $0.propertyName == model.expression
            })?.protocolName else {
                throw Diagnostic(code: "RFNAV003", message: "A destination model must match its root and target declarations.")
            }
            out.open("\(stack.enumName).\(destination.caseName) ->")
            out.line("\(destination.viewName)(\(model.label) = \(model.expression), modifier = modifier)")
            out.close()
        }
        out.close()
        out.depth -= 1
        out.line("}")
    }
}
