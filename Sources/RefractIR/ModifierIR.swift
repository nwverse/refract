public extension ViewNode {
    func appendingModifier(contentsOf additions: [Modifier]) -> ViewNode? {
        var result = self
        for modifier in additions {
            guard let updated = result.appendingModifier(modifier) else { return nil }
            result = updated
        }
        return result
    }

    /// Adds a modifier without losing the type, payload or source location of an existing view.
    /// Containers whose IR does not carry modifiers return nil so the frontend can diagnose them.
    func appendingModifier(_ modifier: Modifier) -> ViewNode? {
        switch self {
        case let .stack(axis, children, modifiers, location):
            return .stack(axis: axis, children: children, modifiers: modifiers + [modifier], location: location)
        case let .text(value, modifiers, location):
            return .text(value, modifiers: modifiers + [modifier], location: location)
        case let .button(label, action, modifiers, location):
            return .button(label: label, action: action, modifiers: modifiers + [modifier], location: location)
        case let .layout(layout, children, modifiers, location):
            return .layout(layout, children: children, modifiers: modifiers + [modifier], location: location)
        case let .scroll(axis, child, modifiers, location):
            return .scroll(axis: axis, child: child, modifiers: modifiers + [modifier], location: location)
        case let .list(children, modifiers, location):
            return .list(children: children, modifiers: modifiers + [modifier], location: location)
        case let .image(source, modifiers, location):
            return .image(source: source, modifiers: modifiers + [modifier], location: location)
        case let .toggle(title, value, modifiers, nativeModifiers, labelsHidden, location):
            return .toggle(title: title, value: value, modifiers: modifiers + [modifier], nativeModifiers: nativeModifiers, labelsHidden: labelsHidden, location: location)
        case let .textInput(placeholder, value, modifiers, location):
            return .textInput(placeholder: placeholder, value: value, modifiers: modifiers + [modifier], location: location)
        case let .secureInput(placeholder, value, reveal, modifiers, location):
            return .secureInput(placeholder: placeholder, value: value, reveal: reveal,
                                modifiers: modifiers + [modifier], location: location)
        case let .label(title, image, modifiers, location):
            return .label(title: title, image: image, modifiers: modifiers + [modifier], location: location)
        case let .divider(modifiers, location):
            return .divider(modifiers: modifiers + [modifier], location: location)
        case let .component(component, location):
            return .component(ComponentReference(name: component.name, arguments: component.arguments,
                children: component.children, modifiers: component.modifiers + [modifier]), location: location)
        case .native, .nativeModifier, .child, .platformView, .conditional, .optionalBinding, .switchExpression,
             .navigationLink, .navigationStack, .tabView, .section, .listItem, .forEach, .spacer:
            return nil
        }
    }
}
