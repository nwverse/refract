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
              let nested = messageBlocks(in: row.body), let parent = nested.parent, let block = nested.block else {
            pendingMessageSources.append((outer, content, currentViewName ?? "", modelType.name))
            return nil
        }
        let items = ListItems(collection: outer, itemName: child.item?.expression ?? "message", itemType: "ChatMessage",
                              keyType: .string, content: content, modelType: modelType.name,
                              messageBlocks: MessageBlockIdentity(content: nested.items.content, parent: parent,
                                                                  blockName: nested.items.itemName,
                                                                  blockArgument: block),
                              location: location)
        return .list(children: [.forEach(items, location: location)], modifiers: [], location: location)
    }

    func linkMessageProjection(siblingScreens: [Screen]) {
        guard !pendingMessageSources.isEmpty else { return }
        for (outer, content, owner, modelType) in pendingMessageSources {
            guard case let .child(child, location) = content,
                  let row = siblingScreens.first(where: { $0.name == child.name }),
                  let nested = messageBlocks(in: row.body), let parent = nested.parent, let block = nested.block else {
                diagnostics.append(Diagnostic(code: "RFMSG001",
                    message: "A ChatMessage list requires a generated MessageRow with bounded block content.",
                    suggestion: "Use MessageRow(message: message) directly in List(model.messages)", location: content.sourceLocation))
                continue
            }
            let items = ListItems(collection: outer, itemName: child.item?.expression ?? "message", itemType: "ChatMessage",
                                  keyType: .string, content: content, modelType: modelType,
                                  messageBlocks: MessageBlockIdentity(content: nested.items.content, parent: parent,
                                                                      blockName: nested.items.itemName,
                                                                      blockArgument: block),
                                  location: location)
            pendingMessageBodies.append((owner, .list(children: [.forEach(items, location: location)], modifiers: [], location: location)))
        }
        for pending in pendingMessageBodies {
            if let index = screens.firstIndex(where: { $0.name == pending.screen }) {
                let original = screens[index]
                screens[index] = Screen(name: original.name, parameters: original.parameters, states: original.states,
                                        modals: original.modals, navigation: original.navigation, body: pending.body,
                                        nativeValues: original.nativeValues, lifecycle: original.lifecycle,
                                        location: original.location)
            } else if let original = pendingMessageOwners[pending.screen] {
                screens.append(Screen(name: original.name, parameters: original.parameters, states: original.states,
                                      navigation: original.navigation, body: pending.body, location: original.location))
            }
        }
        pendingMessageSources.removeAll()
    }

    private func messageBlocks(in node: ViewNode) -> NestedListItems? {
        if case let .messageBlocks(nested, _) = node { return nested }
        for child in node.children {
            if let found = messageBlocks(in: child) { return found }
        }
        return nil
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
