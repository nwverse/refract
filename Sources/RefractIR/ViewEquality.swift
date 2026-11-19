/// Equality walks the finite value trees explicitly instead of consuming one call-stack frame per level.
/// All payloads and source locations are compared; encoding is deliberately not part of value semantics.
extension ViewNode {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        var pending = [(lhs, rhs)]
        while let (lhs, rhs) = pending.popLast() {
            guard lhs.sourceLocation == rhs.sourceLocation else { return false }
            switch (lhs, rhs) {
            case let (.stack(lhsAxis, lhsChildren, lhsModifiers, _),
                      .stack(rhsAxis, rhsChildren, rhsModifiers, _)):
                guard lhsAxis == rhsAxis, lhsModifiers == rhsModifiers,
                      append(lhsChildren, rhsChildren, to: &pending) else { return false }
            case let (.text(lhsText, lhsModifiers, _), .text(rhsText, rhsModifiers, _)):
                guard lhsText == rhsText, lhsModifiers == rhsModifiers else { return false }
            case let (.markdown(lhsDocument, lhsAction, lhsModifiers, _),
                      .markdown(rhsDocument, rhsAction, rhsModifiers, _)):
                guard lhsDocument == rhsDocument, lhsAction == rhsAction,
                      lhsModifiers == rhsModifiers else { return false }
            case let (.button(lhsLabel, lhsAction, lhsModifiers, _),
                      .button(rhsLabel, rhsAction, rhsModifiers, _)):
                guard lhsAction == rhsAction, lhsModifiers == rhsModifiers else { return false }
                pending.append((lhsLabel, rhsLabel))
            case let (.navigationLink(lhsTitle, lhsPath, lhsEnum, lhsDestination, _),
                      .navigationLink(rhsTitle, rhsPath, rhsEnum, rhsDestination, _)):
                guard lhsTitle == rhsTitle, lhsPath == rhsPath, lhsEnum == rhsEnum,
                      lhsDestination == rhsDestination else { return false }
            case let (.navigationStack(lhsStack, _), .navigationStack(rhsStack, _)):
                guard lhsStack.pathName == rhsStack.pathName, lhsStack.rootName == rhsStack.rootName,
                      lhsStack.enumName == rhsStack.enumName, lhsStack.destinations == rhsStack.destinations,
                      lhsStack.models == rhsStack.models,
                      append(lhsStack.content, rhsStack.content, to: &pending) else { return false }
            case let (.tabView(lhsTabs, _), .tabView(rhsTabs, _)):
                guard lhsTabs == rhsTabs else { return false }
            case let (.native(lhsNative, _), .native(rhsNative, _)):
                guard lhsNative == rhsNative else { return false }
            case let (.nativeModifier(lhsChild, lhsOperations, _),
                      .nativeModifier(rhsChild, rhsOperations, _)):
                guard lhsOperations == rhsOperations else { return false }
                pending.append((lhsChild, rhsChild))
            case let (.component(lhsComponent, _), .component(rhsComponent, _)):
                guard lhsComponent.name == rhsComponent.name,
                      lhsComponent.arguments == rhsComponent.arguments,
                      lhsComponent.modifiers == rhsComponent.modifiers,
                      append(lhsComponent.children, rhsComponent.children, to: &pending) else { return false }
            case let (.child(lhsChild, _), .child(rhsChild, _)):
                guard lhsChild == rhsChild else { return false }
            case let (.platformView(lhsAlternatives, _), .platformView(rhsAlternatives, _)):
                guard append(lhsAlternatives.ios, rhsAlternatives.ios, to: &pending),
                      append(lhsAlternatives.android, rhsAlternatives.android, to: &pending),
                      append(lhsAlternatives.harmonyOS, rhsAlternatives.harmonyOS, to: &pending) else { return false }
            case let (.conditional(lhsBranches, _), .conditional(rhsBranches, _)):
                guard lhsBranches.count == rhsBranches.count else { return false }
                for index in lhsBranches.indices {
                    let lhsBranch = lhsBranches[index]
                    let rhsBranch = rhsBranches[index]
                    guard append(lhsBranch.condition, rhsBranch.condition, to: &pending),
                          append(lhsBranch.children, rhsBranch.children, to: &pending) else { return false }
                }
            case let (.optionalBinding(lhsSubject, lhsBinding, lhsChildren, lhsOtherwise, _),
                      .optionalBinding(rhsSubject, rhsBinding, rhsChildren, rhsOtherwise, _)):
                guard lhsSubject == rhsSubject, lhsBinding == rhsBinding,
                      append(lhsChildren, rhsChildren, to: &pending),
                      append(lhsOtherwise, rhsOtherwise, to: &pending) else { return false }
            case let (.switchExpression(lhsSubject, lhsEnum, lhsCases, _),
                      .switchExpression(rhsSubject, rhsEnum, rhsCases, _)):
                guard lhsSubject == rhsSubject, lhsEnum == rhsEnum, lhsCases.count == rhsCases.count else { return false }
                for index in lhsCases.indices {
                    let lhsCase = lhsCases[index]
                    let rhsCase = rhsCases[index]
                    guard lhsCase.name == rhsCase.name, lhsCase.binding == rhsCase.binding,
                          append(lhsCase.children, rhsCase.children, to: &pending) else { return false }
                }
            case let (.layout(lhsLayout, lhsChildren, lhsModifiers, _),
                      .layout(rhsLayout, rhsChildren, rhsModifiers, _)):
                guard lhsLayout.axis == rhsLayout.axis, lhsLayout.alignment == rhsLayout.alignment,
                      lhsLayout.spacing == rhsLayout.spacing, lhsModifiers == rhsModifiers,
                      append(lhsChildren, rhsChildren, to: &pending) else { return false }
            case let (.scroll(lhsAxis, lhsChild, lhsModifiers, _),
                      .scroll(rhsAxis, rhsChild, rhsModifiers, _)):
                guard lhsAxis == rhsAxis, lhsModifiers == rhsModifiers else { return false }
                pending.append((lhsChild, rhsChild))
            case let (.list(lhsChildren, lhsModifiers, _), .list(rhsChildren, rhsModifiers, _)):
                guard lhsModifiers == rhsModifiers,
                      append(lhsChildren, rhsChildren, to: &pending) else { return false }
            case let (.section(lhsHeader, lhsChildren, _), .section(rhsHeader, rhsChildren, _)):
                guard lhsHeader == rhsHeader,
                      append(lhsChildren, rhsChildren, to: &pending) else { return false }
            case let (.listItem(lhsChild, _), .listItem(rhsChild, _)):
                pending.append((lhsChild, rhsChild))
            case let (.forEach(lhsItems, _), .forEach(rhsItems, _)):
                guard lhsItems.collection == rhsItems.collection, lhsItems.modelType == rhsItems.modelType,
                      lhsItems.itemName == rhsItems.itemName, lhsItems.itemType == rhsItems.itemType,
                      lhsItems.key == rhsItems.key, lhsItems.keyType == rhsItems.keyType,
                      lhsItems.contentType == rhsItems.contentType,
                      lhsItems.projection == rhsItems.projection else { return false }
                switch (lhsItems.messageBlocks?.content, rhsItems.messageBlocks?.content) {
                case (nil, nil): break
                case let (lhsContent?, rhsContent?): pending.append((lhsContent, rhsContent))
                default: return false
                }
                pending.append((lhsItems.content, rhsItems.content))
            case let (.messageBlocks(lhsNested, _), .messageBlocks(rhsNested, _)):
                guard lhsNested.parent == rhsNested.parent,
                      lhsNested.message == rhsNested.message, lhsNested.block == rhsNested.block else { return false }
                pending.append((.forEach(lhsNested.items, location: nil), .forEach(rhsNested.items, location: nil)))
            case let (.image(lhsSource, lhsModifiers, _), .image(rhsSource, rhsModifiers, _)):
                guard lhsSource == rhsSource, lhsModifiers == rhsModifiers else { return false }
            case let (.toggle(lhsTitle, lhsValue, lhsModifiers, lhsNativeModifiers, lhsLabelsHidden, _),
                      .toggle(rhsTitle, rhsValue, rhsModifiers, rhsNativeModifiers, rhsLabelsHidden, _)):
                guard lhsTitle == rhsTitle, lhsValue == rhsValue, lhsModifiers == rhsModifiers,
                      lhsNativeModifiers == rhsNativeModifiers, lhsLabelsHidden == rhsLabelsHidden else { return false }
            case let (.textInput(lhsPlaceholder, lhsValue, lhsModifiers, _),
                      .textInput(rhsPlaceholder, rhsValue, rhsModifiers, _)):
                guard lhsPlaceholder == rhsPlaceholder, lhsValue == rhsValue,
                      lhsModifiers == rhsModifiers else { return false }
            case let (.secureInput(lhsPlaceholder, lhsValue, lhsReveal, lhsModifiers, _),
                      .secureInput(rhsPlaceholder, rhsValue, rhsReveal, rhsModifiers, _)):
                guard lhsPlaceholder == rhsPlaceholder, lhsValue == rhsValue, lhsReveal == rhsReveal,
                      lhsModifiers == rhsModifiers else { return false }
            case let (.label(lhsTitle, lhsImage, lhsModifiers, _), .label(rhsTitle, rhsImage, rhsModifiers, _)):
                guard lhsTitle == rhsTitle, lhsImage == rhsImage, lhsModifiers == rhsModifiers else { return false }
            case let (.divider(lhsModifiers, _), .divider(rhsModifiers, _)):
                guard lhsModifiers == rhsModifiers else { return false }
            case (.spacer, .spacer):
                continue
            default:
                return false
            }
        }
        return true
    }
}

extension Expression {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        var pending = [(lhs, rhs)]
        while let (lhs, rhs) = pending.popLast() {
            guard lhs.type == rhs.type, lhs.location == rhs.location else { return false }
            switch (lhs.value, rhs.value) {
            case let (.stringLiteral(lhsText), .stringLiteral(rhsText)),
                 let (.verbatimText(lhsText), .verbatimText(rhsText)),
                 let (.stringKey(lhsText), .stringKey(rhsText)),
                 let (.numberLiteral(lhsText), .numberLiteral(rhsText)),
                 let (.reference(lhsText), .reference(rhsText)),
                 let (.binding(lhsText), .binding(rhsText)):
                guard lhsText == rhsText else { return false }
            case let (.nativeValueProperty(lhsValue), .nativeValueProperty(rhsValue)):
                guard lhsValue == rhsValue else { return false }
            case let (.imageResource(lhsName), .imageResource(rhsName)):
                guard lhsName == rhsName else { return false }
            case let (.boolLiteral(lhsValue), .boolLiteral(rhsValue)):
                guard lhsValue == rhsValue else { return false }
            case let (.layoutSpacing(lhsSpacing), .layoutSpacing(rhsSpacing)):
                guard lhsSpacing == rhsSpacing else { return false }
            case let (.valueProperty(lhsProperty), .valueProperty(rhsProperty)):
                guard lhsProperty == rhsProperty else { return false }
            case let (.localizedText(lhsText), .localizedText(rhsText)):
                guard lhsText.key == rhsText.key,
                      append(lhsText.arguments, rhsText.arguments, to: &pending) else { return false }
            case let (.interpolatedString(lhsSegments), .interpolatedString(rhsSegments)):
                guard lhsSegments.count == rhsSegments.count else { return false }
                for index in lhsSegments.indices {
                    switch (lhsSegments[index], rhsSegments[index]) {
                    case let (.literal(lhsText), .literal(rhsText)):
                        guard lhsText == rhsText else { return false }
                    case let (.expression(lhsExpression), .expression(rhsExpression)):
                        pending.append((lhsExpression, rhsExpression))
                    default:
                        return false
                    }
                }
            case let (.platformValue(lhsAlternatives), .platformValue(rhsAlternatives)):
                pending.append((lhsAlternatives.ios, rhsAlternatives.ios))
                pending.append((lhsAlternatives.android, rhsAlternatives.android))
                pending.append((lhsAlternatives.harmonyOS, rhsAlternatives.harmonyOS))
            case let (.accessibilityAction(lhsAction), .accessibilityAction(rhsAction)):
                guard lhsAction.action == rhsAction.action else { return false }
                pending.append((lhsAction.label, rhsAction.label))
            case let (.accessibilityTraversal(lhsTraversal), .accessibilityTraversal(rhsTraversal)):
                guard lhsTraversal == rhsTraversal else { return false }
            case let (.interactionColor(lhsColor), .interactionColor(rhsColor)):
                guard lhsColor.token == rhsColor.token else { return false }
                pending.append((lhsColor.enabled, rhsColor.enabled))
                pending.append((lhsColor.pressed, rhsColor.pressed))
                pending.append((lhsColor.focused, rhsColor.focused))
            case let (.formField(lhsForm, lhsField), .formField(rhsForm, rhsField)):
                guard lhsForm == rhsForm, lhsField == rhsField else { return false }
            case let (.presence(lhsSubject), .presence(rhsSubject)):
                pending.append((lhsSubject, rhsSubject))
            case let (.formValid(lhsForm), .formValid(rhsForm)):
                guard lhsForm == rhsForm else { return false }
            default:
                return false
            }
        }
        return true
    }
}

private func append(_ lhs: [ViewNode], _ rhs: [ViewNode],
                    to pending: inout [(ViewNode, ViewNode)]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for index in lhs.indices { pending.append((lhs[index], rhs[index])) }
    return true
}

private func append(_ lhs: Expression?, _ rhs: Expression?,
                    to pending: inout [(ViewNode, ViewNode)]) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): return true
    case let (lhs?, rhs?): return lhs == rhs
    default: return false
    }
}

private func append(_ lhs: [Expression], _ rhs: [Expression],
                    to pending: inout [(Expression, Expression)]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for index in lhs.indices { pending.append((lhs[index], rhs[index])) }
    return true
}
