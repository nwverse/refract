import RefractIR
import RefractMapping

extension ComposeBackend {
    func emitNavigationStack(_ stack: NavigationStackNode, isRoot: Bool, location: SourceLocation?,
                             into out: inout KotlinWriter, context: inout Context) throws {
        guard isRoot, let declaration = context.module.enums.first(where: { $0.name == stack.enumName }),
              declaration.isNavigationDestination, declaration.payloadTypes.isEmpty,
              Set(stack.destinations.map(\.caseName)) == Set(declaration.cases) else {
            throw Diagnostic(code: "RFNAV003", message: "A native navigation stack needs exhaustive finite destinations.",
                             suggestion: "Validate the same-file Hashable destination enum in the frontend", location: location)
        }
        // The source NavigationStack is a host boundary, not a second native NavHost. Its root content
        // is emitted as an ordinary component and its destination registrations become a typed switch below.
        for child in stack.content {
            try emit(child, isRoot: isRoot, into: &out, context: &context)
        }
    }

    func emitNavigationLink(title: Expression, destination: String, location: SourceLocation?,
                            into out: inout KotlinWriter, context: inout Context) throws {
        guard let path = context.module.screens.flatMap(\.states).compactMap({ state -> (String, String)? in
            guard case let .navigationPath(name, enumName, _) = state else { return nil }
            return (name, enumName)
        }).first, context.module.enums.first(where: { $0.name == path.1 })?.cases.contains(destination) == true else {
            throw Diagnostic(code: "RFNAV003", message: "A NavigationLink destination is not in the declared path enum.",
                             suggestion: "Use a static case of the source destination enum", location: location)
        }
        context.imports.insert("androidx.compose.material3.Button")
        out.open("Button(onClick = { on\(path.0.uppercasingFirst())Navigate(\(path.1).\(destination)) })")
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
            guard destination.model != nil || context.module.nativeDeclarations.contains(where: {
                $0.name == destination.viewName && $0.parameters.isEmpty
            }) else {
                throw Diagnostic(code: "RFNAV003", message: "A destination must have a typed model or native declaration.")
            }
            out.open("\(stack.enumName).\(destination.caseName) ->")
            if let model = destination.model {
                out.line("\(destination.viewName)(\(model.label) = \(model.expression), modifier = modifier)")
            } else {
                try emitNative(NativeComponent(name: destination.viewName), location: nil, isRoot: false,
                               into: &out, context: &context)
            }
            out.close()
        }
        out.close()
        out.depth -= 1
        out.line("}")
    }
}
