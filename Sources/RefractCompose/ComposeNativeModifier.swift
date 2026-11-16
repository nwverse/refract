import RefractIR

struct ComposeNativeModifier {
    func emit(_ node: ViewNode, operations: [NativeModifier], isRoot: Bool,
              into out: inout KotlinWriter, context: inout ComposeBackend.Context) throws {
        if let action = retainedAction(operations, node: node) {
            try emitRetained(action.action, identity: action.identity, into: &out, context: &context)
        }
        try ComposeBackend().emit(try child(node, with: operations, context: &context),
                                  isRoot: isRoot, into: &out, context: &context)
    }

    private func child(_ node: ViewNode, with operations: [NativeModifier],
                       context: inout ComposeBackend.Context) throws -> ViewNode {
        var seen: Set<String> = []
        var result = node
        if operations.contains(where: {
            if case .retainCallback = $0.operation { return true }
            return false
        }) {
            result = try requireButtonWithRetainedCallback(result)
        }
        for operation in operations {
            let modifier: Modifier
            switch operation.operation {
            case let .testTag(value):
                guard seen.insert("testTag").inserted else { throw duplicate(operation) }
                context.imports.insert("androidx.compose.ui.platform.testTag")
                modifier = Modifier(name: "nativeTestTag", arguments: [value], argumentLabels: [nil],
                                    location: operation.location)
            case let .contentDescription(value):
                guard seen.insert("contentDescription").inserted else { throw duplicate(operation) }
                context.imports.insert("androidx.compose.ui.semantics.contentDescription")
                context.imports.insert("androidx.compose.ui.semantics.semantics")
                modifier = Modifier(name: "nativeContentDescription", arguments: [value], argumentLabels: [nil],
                                    location: operation.location)
            case .retainCallback:
                guard seen.insert("retainCallback").inserted else { throw duplicate(operation) }
                continue
            }
            guard let updated = result.appendingModifier(modifier) else {
                throw Diagnostic(code: "RFNATIVE004",
                    message: "The native operation cannot be attached to this receiver without losing semantics.",
                    suggestion: "Apply it to a concrete view or container with a native modifier receiver.",
                    location: operation.location)
            }
            result = updated
        }
        return result
    }

    private func requireButtonWithRetainedCallback(_ node: ViewNode) throws -> ViewNode {
        guard case let .button(label, action, modifiers, location) = node else {
            throw Diagnostic(code: "RFNATIVE004", message: "Retained callback identity requires an action-owning Button.",
                             suggestion: "Attach retention directly to a Button with a typed model action.",
                             location: node.sourceLocation)
        }
        return .button(label: label, action: action,
                       modifiers: modifiers + [Modifier(name: "retainCallback")], location: location)
    }

    private func retainedAction(_ operations: [NativeModifier], node: ViewNode) -> (action: StateAction, identity: String)? {
        guard case let .button(_, action?, _, _) = node else { return nil }
        for modifier in operations {
            if case let .retainCallback(identity) = modifier.operation { return (action, identity) }
        }
        return nil
    }

    private func emitRetained(_ action: StateAction, identity: String,
                              into out: inout KotlinWriter, context: inout ComposeBackend.Context) throws {
        guard case let .modelMethod(model, _, arguments) = action else {
            throw Diagnostic(code: "RFNATIVE004", message: "Only a declared model action can have retained callback identity.",
                             suggestion: "Use a synchronous model action with explicitly typed captures.")
        }
        context.imports.insert("androidx.compose.runtime.remember")
        let keys = try [model] + arguments.map(\.value).map { value -> String in
            guard case let .reference(reference) = value.value else {
                throw Diagnostic(code: "RFNATIVE004", message: "Retained callback captures must be explicit stable references.",
                                 suggestion: "Capture the model and a declared item identity, not a computed or literal value.",
                                 location: value.location)
            }
            if let item = context.retainedItem, let itemType = context.module.itemTypes.first(where: {
                $0.name == item.type
            }) {
                let parts = reference.split(separator: ".")
                guard parts.count == 2, parts[0] == item.name,
                      itemType.identity.name == parts[1] else {
                    throw Diagnostic(code: "RFNATIVE004",
                        message: "A retained item callback must capture its declared stable item identity.",
                        suggestion: "Capture the Identifiable item's stored id, not a display property or mutable value.",
                        location: value.location)
                }
            }
            return reference
        }
        out.line("val onClick = remember(\((keys + ["\"\(identity)\""]).joined(separator: ", "))) {")
        out.depth += 1
        out.line("{ \(try ComposeBackend().renderAction(action, context: &context)) }")
        out.depth -= 1
        out.line("}")
    }

    private func duplicate(_ modifier: NativeModifier) -> Diagnostic {
        Diagnostic(code: "RFNATIVE004", message: "A native modifier operation may occur only once per receiver.",
                   suggestion: "Combine the intended value into one explicit operation.", location: modifier.location)
    }
}
