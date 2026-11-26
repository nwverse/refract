import RefractIR
import RefractMapping

struct ComposeNativeModifier {
    func emit(_ node: ViewNode, operations: [NativeModifier], isRoot: Bool,
              into out: inout KotlinWriter, context: inout ComposeBackend.Context) throws {
        // Selection edits replace the TextField receiver with a dedicated selection-aware TextField call.
        if let selection = operations.first(where: { if case .textSelection = $0.operation { true } else { false } }),
           case let .textSelection(start, end, action) = selection.operation {
            try emitSelectionField(node, start: start, end: end, action: action, isRoot: isRoot,
                                   into: &out, context: &context)
            return
        }
        // Drag and drop operations wrap the child in dedicated Box calls that own the native gestures.
        let drag = operations.first { if case .dragPayload = $0.operation { true } else { false } }
        let drop = operations.first { if case .dropTarget = $0.operation { true } else { false } }
        if drag != nil || drop != nil {
            try emitDragDropBox(node, operations: operations, isRoot: isRoot, into: &out, context: &context)
            return
        }
        if let action = retainedAction(operations, node: node) {
            try emitRetained(action.action, identity: action.identity, into: &out, context: &context)
        }
        try ComposeBackend().emit(try child(node, with: operations, context: &context),
                                  isRoot: isRoot, into: &out, context: &context)
    }

    private func emitSelectionField(_ node: ViewNode, start: Expression, end: Expression, action: String,
                                    isRoot: Bool, into out: inout KotlinWriter,
                                    context: inout ComposeBackend.Context) throws {
        guard case let .textInput(placeholder, value, modifiers, location) = node else {
            throw Diagnostic(code: "RFNATIVE005",
                message: "Text selection editing requires a TextField receiver.",
                suggestion: "Attach `.textSelection(start:end:action:)` directly to the TextField it edits.",
                location: node.sourceLocation)
        }
        guard let placeholder, case let .localizedText = placeholder.value else {
            throw Diagnostic(code: "RFNATIVE005",
                message: "A selection-aware TextField requires a localized placeholder.",
                suggestion: "Use a canonical settings.* key.", location: location)
        }
        guard case let .valueProperty(.state(name)) = value.value else {
            throw Diagnostic(code: "RFNATIVE005",
                message: "A selection-aware TextField must read its value from a local @State String.",
                suggestion: "Bind the TextField to `@State private var text: String`.", location: value.location)
        }
        // The model that owns the action must be a declared model on this screen.
        guard let resolved = context.currentModel(forActionNamed: action, parameters: [
            ModelParameter(externalName: "start", localName: "start", type: .int),
            ModelParameter(externalName: "end", localName: "end", type: .int),
            ModelParameter(externalName: "replacement", localName: "replacement", type: .string),
        ]) else {
            throw Diagnostic(code: "RFNATIVE005",
                message: "Selection action `\(action)` must name a method on a declared model.",
                suggestion: "Declare `func \(action)(start: Int, end: Int, replacement: String)` on a `RefractModel` protocol used by this screen.",
                location: location)
        }
        let label = try LocalizedTextEmitter.compose(placeholder, mapping: context.mapping,
                                                      packageName: context.packageName) {
            try ComposeBackend().renderExpression($0, context: &context)
        }
        let startExpr = try ComposeBackend().renderExpression(start, context: &context)
        let endExpr = try ComposeBackend().renderExpression(end, context: &context)
        context.imports.insert("androidx.compose.material3.Text")
        context.imports.insert("androidx.compose.material3.TextField")
        context.imports.insert("androidx.compose.ui.res.stringResource")
        context.imports.insert("androidx.compose.ui.text.TextRange")
        context.imports.insert("androidx.compose.ui.text.input.TextFieldValue")
        let modifierChain = try ComposeBackend().modifierChain(modifiers, isRoot: isRoot, into: &out, context: &context)
        out.open("TextField(")
        out.line("value = TextFieldValue(text = \(name), selection = TextRange(\(startExpr), \(endExpr))),")
        out.line("onValueChange = { updated ->")
        out.depth += 1
        out.line("\(name) = updated.text")
        out.line("\(resolved.model).\(action)(\(resolved.labels[0]) = updated.selection.start, \(resolved.labels[1]) = updated.selection.end, \(resolved.labels[2]) = updated.text)")
        out.depth -= 1
        out.line("},")
        out.line("label = { Text(text = \(label)) },")
        out.line("modifier = \(modifierChain),")
        out.depth -= 1
        out.line(")")
    }

    private func emitDragDropBox(_ node: ViewNode, operations: [NativeModifier], isRoot: Bool,
                                 into out: inout KotlinWriter,
                                 context: inout ComposeBackend.Context) throws {
        var drag: (kind: String, value: Expression)?
        var drop: (kind: String, action: String)?
        for op in operations {
            switch op.operation {
            case let .dragPayload(kind, value):
                drag = (kind, value)
            case let .dropTarget(kind, action):
                drop = (kind, action)
            case .textSelection, .retainCallback, .contentType, .testTag, .contentDescription:
                throw Diagnostic(code: "RFNATIVE005",
                    message: "This operation cannot be combined with drag/drop on the same receiver.",
                    suggestion: "Apply drag and drop to a dedicated wrapper Box.",
                    location: op.location)
            }
        }
        let resolvedDrop: (model: String, labels: [String])? = try drop.map { drop in
            guard let resolved = context.currentModel(forActionNamed: drop.action, parameters: [
                ModelParameter(externalName: "kind", localName: "kind", type: .string),
                ModelParameter(externalName: "payload", localName: "payload", type: .string),
            ]) else {
                throw Diagnostic(code: "RFNATIVE005",
                    message: "Drop action `\(drop.action)` must name a method on a declared model.",
                    suggestion: "Declare `func \(drop.action)(kind: String, payload: String)` on a `RefractModel` protocol used by this screen.",
                    location: node.sourceLocation)
            }
            return resolved
        }
        // The emitted code uses the Compose Foundation drag-and-drop API directly, which is experimental.
        // We depend only on the platform SDK, never on a runtime bridge.
        context.imports.insert("androidx.compose.foundation.ExperimentalFoundationApi")
        context.imports.insert("androidx.compose.foundation.draganddrop.dragAndDropSource")
        context.imports.insert("androidx.compose.foundation.draganddrop.dragAndDropTarget")
        context.imports.insert("androidx.compose.foundation.layout.Box")
        context.imports.insert("androidx.compose.runtime.remember")
        context.optIns.insert("androidx.compose.foundation.ExperimentalFoundationApi")
        // Box(
        //     modifier = Modifier
        //         .dragAndDropSource(...)
        //         .dragAndDropTarget(...)
        // ) {
        //     <child>
        // }
        out.open("Box(")
        out.line("modifier = Modifier")
        out.depth += 1
        if let drag {
            let value = try ComposeBackend().renderExpression(drag.value, context: &context)
            context.imports.insert("android.content.ClipData")
            context.imports.insert("androidx.compose.ui.draganddrop.DragAndDropTransferData")
            out.line(".dragAndDropSource(")
            out.depth += 1
            out.line("transferData = {")
            out.depth += 1
            out.line("DragAndDropTransferData(")
            out.depth += 1
            out.line("clipData = ClipData.newPlainText(\"\(drag.kind)\", \(value)),")
            out.depth -= 1
            out.line(")")
            out.depth -= 1
            out.line("}")
            out.depth -= 1
            out.line(")")
        }
        if let drop, let resolvedDrop {
            context.imports.insert("androidx.compose.ui.draganddrop.DragAndDropEvent")
            context.imports.insert("androidx.compose.ui.draganddrop.DragAndDropTarget")
            context.imports.insert("androidx.compose.ui.draganddrop.toAndroidDragEvent")
            out.line(".dragAndDropTarget(")
            out.depth += 1
            out.line("shouldStartDragAndDrop = { event ->")
            out.depth += 1
            out.line("event.toAndroidDragEvent().clipDescription?.hasMimeType(\"text/plain\") == true")
            out.depth -= 1
            out.line("},")
            out.line("target = remember {")
            out.depth += 1
            out.line("object : DragAndDropTarget {")
            out.depth += 1
            out.line("override fun onDrop(event: DragAndDropEvent): Boolean {")
            out.depth += 1
            out.line("val text = event.toAndroidDragEvent().clipData?.getItemAt(0)?.text?.toString() ?: return false")
            out.line("if (text.isEmpty()) return false")
            out.line("\(resolvedDrop.model).\(drop.action)(\(resolvedDrop.labels[0]) = \"\(drop.kind)\", \(resolvedDrop.labels[1]) = text)")
            out.line("return true")
            out.depth -= 1
            out.line("}")
            out.depth -= 1
            out.line("}")
            out.depth -= 1
            out.line("},")
            out.depth -= 1
            out.line(")")
        }
        // Close the modifier chain depth, then close Box's parameter list at the Box's own depth.
        out.depth -= 1  // exit modifier chain
        out.depth -= 1  // exit Box( arguments
        out.line(") {")
        out.depth += 1  // enter Box content lambda
        // Emit the underlying node without its drag/drop operations.
        let remaining = operations.filter {
            switch $0.operation {
            case .dragPayload, .dropTarget: false
            default: true
            }
        }
        if remaining.isEmpty {
            try ComposeBackend().emit(node, isRoot: false, into: &out, context: &context)
        } else {
            try ComposeNativeModifier().emit(node, operations: remaining, isRoot: false, into: &out, context: &context)
        }
        out.depth -= 1
        out.line("}")
    }

    private func child(_ node: ViewNode, with operations: [NativeModifier],
                       context: inout ComposeBackend.Context) throws -> ViewNode {
        var seen: Set<String> = []
        var result = node
        if case .button = node, operations.contains(where: {
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
            case .contentType:
                throw Diagnostic(code: "RFNATIVE004",
                    message: "Row content type belongs on a generated child, not a wrapped native modifier receiver.",
                    suggestion: "Apply `.contentType` directly to the generated child row", location: operation.location)
            case .retainCallback:
                guard seen.insert("retainCallback").inserted else { throw duplicate(operation) }
                continue
            case .textSelection, .dragPayload, .dropTarget:
                throw Diagnostic(code: "RFNATIVE005",
                    message: "Selection and drag/drop operations are handled by their dedicated emit paths.",
                    suggestion: "This is an internal error in the generator; please report it.",
                    location: operation.location)
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
            if let item = context.retainedItem, let itemType = context.itemTypes.first(where: {
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
