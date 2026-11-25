import RefractIR
import SwiftSyntax

/// The bounded message snapshot is UI data, not a generated streaming state machine.
/// The application owns append/update/finalize ordering, validation and capacity.
extension Builder {
    func messageBlockInputScreen(_ node: StructDeclSyntax, members: MemberBlockItemListSyntax) -> Screen? {
        guard let message = itemTypes.first(where: { $0.name == "ChatMessage" }),
              let block = itemTypes.first(where: { $0.name == "ChatBlock" }) else { return nil }
        var inputs: [ScreenParameter] = []
        var parentName: String?
        var blockName: String?
        var body: VariableDeclSyntax?
        for member in members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.attributes.isEmpty, variable.modifiers.isEmpty,
                  (variable.bindingSpecifier.tokenKind == .keyword(.let) ||
                   (variable.bindingSpecifier.tokenKind == .keyword(.var) &&
                    variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "body")), variable.bindings.count == 1,
                  let binding = variable.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  name == "body" || (binding.initializer == nil && binding.accessorBlock == nil) else {
                error("RFMSG001", "A message-block child accepts only immutable message/block inputs and its body.",
                      "Use `let message: ChatMessage` and `let block: ChatBlock`", at: member)
                return nil
            }
            if name == "body" {
                body = variable
                continue
            }
            guard let annotation = binding.typeAnnotation?.type.trimmedDescription,
                  ["ChatMessage", "ChatBlock"].contains(annotation) else {
                error("RFMSG001", "Message-block inputs must be explicitly typed ChatMessage and ChatBlock.",
                      "Do not pass arbitrary models, scalars or sibling items", at: member)
                return nil
            }
            let type = annotation == "ChatMessage" ? message : block
            if annotation == "ChatMessage" { parentName = name }
            if annotation == "ChatBlock" { blockName = name }
            inputs.append(ScreenParameter(name: name, type: type.identity.type, itemType: type.name,
                                          location: location(of: member)))
        }
        guard inputs.count == 2, inputs.compactMap(\.itemType).sorted() == ["ChatBlock", "ChatMessage"],
              let parentName, let blockName, let body, let binding = body.bindings.first,
              let accessors = binding.accessorBlock?.accessors, case let .getter(items) = accessors else {
            error("RFMSG001", "MessageBlock requires one ChatMessage input, one ChatBlock input and one expression body.",
                  "Keep the checked parent and block identities explicit", at: node.name)
            return nil
        }
        let savedParameters = parameters
        let savedItem = currentListItem
        let savedType = currentListItemType
        let savedModels = currentModels
        let savedStates = currentStates
        parameters = inputs
        currentListItem = parentName
        currentListItemType = message
        currentModels = []
        currentStates = []
        currentMessageBlockNames = (parentName, blockName)
        defer {
            parameters = savedParameters
            currentListItem = savedItem
            currentListItemType = savedType
            currentModels = savedModels
            currentStates = savedStates
            currentMessageBlockNames = nil
        }
        guard let root = viewStatements(items, body: binding) else { return nil }
        return Screen(name: node.name.text, parameters: inputs, states: [], body: root,
                      location: location(of: node.name))
    }

    func messageBlocks(_ call: FunctionCallExprSyntax) -> ViewNode? {
        guard currentListItem != nil, currentListItemType?.name == "ChatMessage",
              currentListItemType?.messageProjection == true else {
            error("RFMSG001", "ForEach inside a dynamic row is supported only for bounded ChatMessage blocks.",
                  "Use a flat model collection, or ForEach(message.blocks) directly inside a ChatMessage row's VStack", at: call)
            return nil
        }
        guard let parentName = currentListItem, let parent = currentListItemType,
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "ForEach",
              call.arguments.count == 1, call.arguments.first?.label == nil,
              call.additionalTrailingClosures.isEmpty,
              let collectionExpression = call.arguments.first?.expression,
              let member = collectionExpression.as(MemberAccessExprSyntax.self),
              member.declName.argumentNames == nil, member.declName.baseName.text == "blocks",
              member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == parentName,
              let descriptor = parent.properties.first(where: { $0.name == "blocks" })?.collection,
              descriptor.owner == "ChatMessage", descriptor.property == "blocks",
              let block = itemTypes.first(where: { $0.name == descriptor.itemType }),
              block.messageProjection, block.name == "ChatBlock",
              let closure = call.trailingClosure,
              let blockName = closureItemName(closure), blockName != parentName else {
            error("RFMSG001", "Message blocks require exactly `ForEach(message.blocks) { block in ... }` in a ChatMessage row.",
                  "Use the declared ChatBlock collection with a distinct item name and one non-scrolling content view", at: call)
            return nil
        }
        let previousItem = currentListItem
        let previousType = currentListItemType
        let previousMessageParent = currentMessageParent
        currentMessageParent = (parentName, parent)
        currentListItem = blockName
        currentListItemType = block
        defer {
            currentListItem = previousItem
            currentListItemType = previousType
            currentMessageParent = previousMessageParent
        }
        let row = children(of: closure) ?? []
        var nestedCall: (message: ChildView.Argument, block: ChildView.Argument)?
        var declarationError = false
        if row.count == 1, case let .child(child, _) = row[0],
           let declaration = viewDeclarations[child.name] {
            let names = declaration.memberBlock.members.compactMap { member in
                member.decl.as(VariableDeclSyntax.self)?.bindings.first?.pattern
                    .as(IdentifierPatternSyntax.self)?.identifier.text
            }.filter { $0 != "body" }
            if names.count != 2 || !names.contains("message") || !names.contains("block") {
                error("RFMSG001", "The bounded message-block child must declare `let message: ChatMessage` and `let block: ChatBlock`.",
                      "Keep one parent and one block input so projection identity stays explicit", at: declaration.name)
                declarationError = true
            }
            if child.arguments.first(where: { $0.expression == parentName })?.label != "message" ||
                child.arguments.first(where: { $0.expression == blockName })?.label != "block" {
                error("RFMSG001", "Pass the current parent as `message:` and its block as `block:`.",
                      "Use `MessageBlock(message: message, block: block)`", at: call)
                declarationError = true
            }
        }
        if !declarationError, row.count == 1, case let .child(child, _) = row[0],
           let declaration = viewDeclarations[child.name],
           let messageArgument = child.arguments.first(where: { $0.expression == parentName }),
           let blockArgument = child.arguments.first(where: { $0.expression == blockName }),
           childItemParameter(declaration, named: messageArgument.label, itemType: parent.name),
           childItemParameter(declaration, named: blockArgument.label, itemType: block.name),
           child.arguments.count == 2,
           child.models.contains(where: { $0.label == "message" && $0.expression == parentName }) ||
            (child.models.isEmpty && child.arguments.contains(where: { $0.label == "message" && $0.expression == parentName })),
           child.item?.label == "block", child.item?.expression == blockName {
            nestedCall = (messageArgument, blockArgument)
        } else {
            error("RFMSG001", "A message block must be a generated child taking the current ChatMessage and ChatBlock.",
                  "Use `MessageBlock(message: message, block: block)` with matching immutable item inputs", at: closure)
        }
        guard let content = row.first else { return nil }
        let items = ListItems(collection: Expression(.reference("\(parentName).blocks"),
                                                     location: location(of: collectionExpression)),
                              itemName: blockName, itemType: block.name,
                              key: block.identity.name, keyType: block.identity.type,
                              content: content, location: location(of: call))
        guard let nestedCall else {
            error("RFMSG001", "A message block must be a generated child taking the current ChatMessage and ChatBlock.",
                  "Use `MessageBlock(message: message, block: block)` with matching immutable item inputs", at: closure)
            return nil
        }
        return .messageBlocks(NestedListItems(items, parent: parentName,
                                              message: nestedCall.message, block: nestedCall.block),
                              location: location(of: call))
    }

    func attachMessageSource(_ outer: Expression, to content: ViewNode) -> ViewNode? {
        guard case let .child(child, location) = content,
              case let .valueProperty(.model(model, property)) = outer.value,
              let reference = currentModels.first(where: { $0.propertyName == model }),
              let modelType = models.first(where: { $0.name == reference.protocolName }),
              modelType.properties.contains(where: { $0.name == property && $0.collection?.itemType == "ChatMessage" }) else {
            diagnostics.append(Diagnostic(code: "RFMSG001",
                message: "A ChatMessage list requires a generated MessageRow with bounded block content.",
                suggestion: "Use MessageRow(message: message) directly in List(model.messages)", location: content.sourceLocation))
            return nil
        }
        guard let row = screens.first(where: { $0.name == child.name }),
              let resolved = resolvedMessageList(outer: outer, content: child, modelType: modelType.name,
                                                row: row, location: location) else {
            return deferredMessageList(outer: outer, content: child, modelType: modelType.name, location: location)
        }
        return resolved
    }

    private func deferredMessageList(outer: Expression, content: ChildView, modelType: String,
                                     location: RefractIR.SourceLocation?) -> ViewNode {
        pendingMessageSources.append((outer, .child(content, location: location), currentViewName ?? "", modelType))
        // This marker remains inside the parsed source tree until the sibling row is checked.
        // The linker either replaces it or reports RFMSG001; no backend can receive it as valid input.
        let items = ListItems(collection: outer, itemName: content.item?.expression ?? "message",
                              itemType: "ChatMessage", keyType: .string, content: .child(content, location: location),
                              modelType: modelType, location: location)
        return .list(children: [.forEach(items, location: location)], modifiers: [], location: location)
    }

    func linkMessageProjection(siblingScreens: [Screen]) {
        guard !pendingMessageSources.isEmpty else { return }
        for (outer, content, owner, modelType) in pendingMessageSources {
            guard case let .child(child, location) = content,
                  let row = siblingScreens.first(where: { $0.name == child.name }) else {
                rejectMessageLink("A ChatMessage list requires a generated MessageRow with bounded block content.",
                                  suggestion: "Use MessageRow(message: message) directly in List(model.messages)",
                                  location: content.sourceLocation)
                continue
            }
            guard let index = screens.firstIndex(where: { $0.name == owner }),
                  let body = replacingDeferredMessageList(in: screens[index].body, outer: outer, content: child,
                                                          modelType: modelType, row: row, location: location) else {
                rejectMessageLink("A deferred ChatMessage list could not be linked to its checked source position.",
                                  suggestion: "Keep List(model.messages) in one generated screen with its checked MessageRow",
                                  location: content.sourceLocation)
                continue
            }
            let original = screens[index]
            screens[index] = Screen(name: original.name, parameters: original.parameters, states: original.states,
                                    modals: original.modals, navigation: original.navigation, body: body,
                                    nativeValues: original.nativeValues, lifecycle: original.lifecycle,
                                    location: original.location)
            pendingMessageBodies.append((owner, body))
        }
        pendingMessageSources.removeAll()
    }

    private func rejectMessageLink(_ message: String, suggestion: String, location: RefractIR.SourceLocation?) {
        let diagnostic = Diagnostic(code: "RFMSG001", message: message, suggestion: suggestion, location: location)
        diagnostics.append(diagnostic)
        messageLinkDiagnostics.append(diagnostic)
    }

    private func resolvedMessageItems(outer: Expression, content: ChildView, modelType: String,
                                      row: Screen, location: RefractIR.SourceLocation?) -> ListItems? {
        guard let nested = messageBlocks(in: row.body), let parent = nested.parent, let block = nested.block else {
            return nil
        }
        return ListItems(collection: outer, itemName: content.item?.expression ?? "message", itemType: "ChatMessage",
                         keyType: .string, content: .child(content, location: location), modelType: modelType,
                         messageBlocks: MessageBlockIdentity(content: nested.items.content, parent: parent,
                                                             blockName: nested.items.itemName,
                                                             blockArgument: block),
                         location: location)
    }

    private func resolvedMessageList(outer: Expression, content: ChildView, modelType: String,
                                     row: Screen, location: RefractIR.SourceLocation?) -> ViewNode? {
        guard let items = resolvedMessageItems(outer: outer, content: content, modelType: modelType,
                                               row: row, location: location) else { return nil }
        return .list(children: [.forEach(items, location: location)], modifiers: [], location: location)
    }

    private func replacingDeferredMessageList(in root: ViewNode, outer: Expression, content: ChildView,
                                              modelType: String, row: Screen,
                                              location: RefractIR.SourceLocation?) -> ViewNode? {
        guard let resolved = resolvedMessageItems(outer: outer, content: content, modelType: modelType,
                                                  row: row, location: location) else { return nil }
        var replaced = false
        func replace(_ node: ViewNode) -> ViewNode {
            if replaced { return node }
            if case let .list(children, modifiers, listLocation) = node, children.count == 1,
               case let .forEach(items, _) = children[0], items.itemType == "ChatMessage",
               items.collection == outer, items.messageBlocks == nil, items.location == location,
               case let .child(candidate, _) = items.content, candidate == content {
                replaced = true
                // Replace only the deferred child; the original wrapper owns its modifiers and source location.
                return .list(children: [.forEach(resolved, location: location)], modifiers: modifiers,
                             location: listLocation)
            }
            switch node {
            case let .stack(axis, children, modifiers, location):
                return .stack(axis: axis, children: children.map(replace), modifiers: modifiers, location: location)
            case let .layout(layout, children, modifiers, location):
                return .layout(layout, children: children.map(replace), modifiers: modifiers, location: location)
            case let .list(children, modifiers, location):
                return .list(children: children.map(replace), modifiers: modifiers, location: location)
            case let .scroll(axis, child, modifiers, location):
                return .scroll(axis: axis, child: replace(child), modifiers: modifiers, location: location)
            case let .listItem(child, location):
                return .listItem(child: replace(child), location: location)
            case let .nativeModifier(child, operations, location):
                return .nativeModifier(child: replace(child), operations: operations, location: location)
            case let .button(label, action, modifiers, location):
                return .button(label: replace(label), action: action, modifiers: modifiers, location: location)
            case let .section(header, children, location):
                return .section(header: header, children: children.map(replace), location: location)
            case let .component(component, location):
                return .component(ComponentReference(name: component.name, arguments: component.arguments,
                    children: component.children.map(replace), modifiers: component.modifiers), location: location)
            case let .forEach(items, location):
                let updated = ListItems(collection: items.collection, itemName: items.itemName, itemType: items.itemType,
                                        key: items.key, keyType: items.keyType, content: replace(items.content),
                                        contentType: items.contentType, projection: items.projection,
                                        modelType: items.modelType, messageBlocks: items.messageBlocks,
                                        location: items.location)
                return .forEach(updated, location: location)
            case let .messageBlocks(nested, location):
                let items = nested.items
                let updated = ListItems(collection: items.collection, itemName: items.itemName, itemType: items.itemType,
                                        key: items.key, keyType: items.keyType, content: replace(items.content),
                                        contentType: items.contentType, projection: items.projection,
                                        modelType: items.modelType, messageBlocks: items.messageBlocks,
                                        location: items.location)
                return .messageBlocks(NestedListItems(updated, parent: nested.parent, message: nested.message,
                                                      block: nested.block), location: location)
            case let .horizontalSections(sections, location):
                let rows = sections.rows
                let updated = HorizontalItemCollection(property: rows.property, itemName: rows.itemName,
                    itemType: rows.itemType, key: rows.key, keyType: rows.keyType, content: replace(rows.content),
                    location: rows.location)
                return .horizontalSections(HorizontalSectionCollection(collection: sections.collection,
                    modelType: sections.modelType, sectionName: sections.sectionName, sectionType: sections.sectionType,
                    sectionKey: sections.sectionKey, sectionKeyType: sections.sectionKeyType,
                    titleProperty: sections.titleProperty, rows: updated, location: sections.location), location: location)
            case let .conditional(branches, location):
                return .conditional(conditions: branches.map {
                    ViewNode.ConditionBranch(condition: $0.condition, children: $0.children.map(replace))
                }, location: location)
            case let .optionalBinding(subject, binding, children, otherwise, location):
                return .optionalBinding(subject: subject, binding: binding, children: children.map(replace),
                                        otherwise: otherwise.map(replace), location: location)
            case let .switchExpression(subject, enumName, cases, location):
                return .switchExpression(subject: subject, enumName: enumName, cases: cases.map {
                    SwitchCase(name: $0.name, binding: $0.binding, children: $0.children.map(replace))
                }, location: location)
            case let .navigationStack(stack, location):
                return .navigationStack(NavigationStackNode(pathName: stack.pathName, rootName: stack.rootName,
                    enumName: stack.enumName, content: stack.content.map(replace), destinations: stack.destinations,
                    models: stack.models), location: location)
            case let .platformView(alternatives, location):
                return .platformView(PlatformAlternatives(ios: alternatives.ios.map(replace),
                    android: alternatives.android.map(replace), harmonyOS: alternatives.harmonyOS.map(replace)),
                    location: location)
            default:
                return node
            }
        }
        let body = replace(root)
        return replaced ? body : nil
    }

    func validateMessageRowShape(_ root: ViewNode) -> Bool {
        guard containsMessageBlocks(root), messageBlocks(in: root) == nil else { return true }
        diagnostics.append(Diagnostic(code: "RFMSG001",
            message: "ForEach(message.blocks) must be a direct child of the message row's VStack.",
            suggestion: "Keep the bounded ForEach directly inside the row's non-scrolling VStack",
            location: root.sourceLocation))
        return false
    }

    private func containsMessageBlocks(_ node: ViewNode) -> Bool {
        if case .messageBlocks = node { return true }
        return node.children.contains(where: containsMessageBlocks)
    }

    private func messageBlocks(in node: ViewNode) -> NestedListItems? {
        guard case let .stack(axis, children, _, _) = node, axis == .vertical else { return nil }
        return children.compactMap { child -> NestedListItems? in
            guard case let .messageBlocks(nested, _) = child else { return nil }
            return nested
        }.first
    }

    func validateMessageProjection(_ module: Module) {
        let messages = itemTypes.filter { $0.name == "ChatMessage" }
        guard let message = messages.first, messages.count == 1 else {
            if messages.isEmpty { return }
            diagnostics.append(Diagnostic(code: "RFMSG001",
                message: "The bounded message projection accepts one explicit ChatMessage declaration.",
                suggestion: "Share the checked declaration through the compilation input set", location: nil))
            return
        }
        if itemTypes.contains(where: { $0.name == "ChatBlock" && !$0.messageProjection }) {
            diagnostics.append(Diagnostic(code: "RFMSG001",
                message: "ChatBlock must be an immutable Identifiable snapshot with independent String id and text.",
                suggestion: "Declare `let id: String` and `let text: String`", location: nil))
            return
        }
        guard message.messageProjection,
              message.identity.type == .string,
              message.properties.map(\.name) == ["id", "revision", "blocks", "finalized"],
              message.properties.map(\.declaredType) == ["String", "UInt64", "[ChatBlock]", "Bool"],
              message.properties.first(where: { $0.name == "revision" })?.type == .revision,
              let blocks = message.properties.first(where: { $0.name == "blocks" })?.collection,
              blocks.owner == "ChatMessage", blocks.property == "blocks", blocks.itemType == "ChatBlock",
              let block = itemTypes.first(where: { $0.name == "ChatBlock" }),
              block.messageProjection, block.identity.type == .string,
              block.properties.map(\.name) == ["id", "text"],
              block.properties.map(\.declaredType) == ["String", "String"] else {
            diagnostics.append(Diagnostic(code: "RFMSG001",
                message: "ChatMessage must be an immutable Identifiable snapshot with String id, UInt64 revision, [ChatBlock] blocks and Bool finalized.",
                suggestion: "Declare `let id: String`, `let revision: UInt64`, `let blocks: [ChatBlock]`, `let finalized: Bool`; ChatBlock stores String id and text",
                location: message.location))
            return
        }

        func visit(_ node: ViewNode) {
            if case let .messageBlocks(nested, location) = node {
                guard nested.items.itemType == "ChatBlock",
                      nested.items.key == "id", nested.items.keyType == .string,
                      case let .reference(source) = nested.items.collection.value, source.hasSuffix(".blocks") else {
                    diagnostics.append(Diagnostic(code: "RFMSG001",
                        message: "A message block ForEach must belong directly to a valid ChatMessage snapshot.",
                        suggestion: "Keep the checked parent/item identity in the shared IR", location: location))
                    return
                }
            }
            for child in node.children { visit(child) }
        }
        for screen in module.screens { visit(screen.body) }
    }

}
