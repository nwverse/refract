/// A native-only extension of the scalar value boundary; it never enters models or local state.
public enum NativeParameterType: String, Codable, Sendable {
    case string, bool, double, int, image, stringKey, remoteImageLoader, action, actionString
    case selectionContent, selectionContextAction

    public var scalar: ValueType? {
        switch self {
        case .string: .string
        case .bool: .bool
        case .double: .double
        case .int: .int
        case .image, .stringKey, .remoteImageLoader, .action, .actionString,
             .selectionContent, .selectionContextAction: nil
        }
    }

    public var sourceName: String {
        switch self {
        case .string: "String"
        case .bool: "Bool"
        case .double: "Double"
        case .int: "Int"
        case .image: "Image"
        case .stringKey: "LocalizedStringKey"
        case .remoteImageLoader: "RemoteImageLoader"
        case .action: "() -> Void"
        case .actionString: "(String) -> Void"
        case .selectionContent: "RefractSelectionContent"
        case .selectionContextAction: "(RefractSelectionContext) -> Void"
        }
    }
}

/// A typed parameter in a native component's Swift declaration or call.
public struct NativeParameter: Codable, Equatable, Sendable {
    public let label: String
    public let type: NativeParameterType
    public let location: SourceLocation?

    public init(label: String, type: NativeParameterType, location: SourceLocation? = nil) {
        self.label = label
        self.type = type
        self.location = location
    }
}

/// The source-owned signature. Its SwiftUI body remains the iOS implementation.
public struct NativeDeclaration: Codable, Equatable, Sendable {
    public let name: String
    public let parameters: [NativeParameter]
    public let kind: Kind
    public let location: SourceLocation?

    public init(name: String, parameters: [NativeParameter], kind: Kind = .component,
                location: SourceLocation? = nil) {
        self.name = name
        self.parameters = parameters
        self.kind = kind
        self.location = location
    }

    private enum CodingKeys: String, CodingKey { case name, parameters, kind, location }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        parameters = try values.decode([NativeParameter].self, forKey: .parameters)
        kind = try values.decodeIfPresent(Kind.self, forKey: .kind) ?? .component
        location = try values.decodeIfPresent(SourceLocation.self, forKey: .location)
    }
}

public struct NativeArgument: Codable, Equatable, Sendable {
    public let label: String
    public let expression: Expression?
    public let action: StateAction?
    public let type: NativeParameterType?
    public let location: SourceLocation?
    /// Closed literal selection content, never an arbitrary serialized payload.
    public let selection: SelectionContent?

    private enum CodingKeys: String, CodingKey { case label, expression, action, type, location, selection }

    public init(label: String, expression: Expression? = nil, action: StateAction? = nil,
                selection: SelectionContent? = nil, type: NativeParameterType?, location: SourceLocation? = nil) {
        self.label = label
        self.expression = expression
        self.action = action
        self.selection = selection
        self.type = type
        self.location = location
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        label = try values.decode(String.self, forKey: .label)
        expression = try values.decodeIfPresent(Expression.self, forKey: .expression)
        action = try values.decodeIfPresent(StateAction.self, forKey: .action)
        selection = try values.decodeIfPresent(SelectionContent.self, forKey: .selection)
        type = try values.decodeIfPresent(NativeParameterType.self, forKey: .type)
        location = try values.decodeIfPresent(SourceLocation.self, forKey: .location)
    }
}

/// A closed, typed native operation. There is deliberately no target-source payload.
public struct NativeModifier: Codable, Equatable, Sendable {
    public enum Operation: Codable, Equatable, Sendable {
        case testTag(Expression)
        case contentDescription(Expression)
        case retainCallback(identity: String)
        case contentType(String)
        /// Bounded text selection editing on a text input.
        /// `start`/`end` are typed Int expressions describing the current selection; `action`
        /// names a synchronous model method with signature `(start: Int, end: Int, replacement: String)`
        /// that the platform invokes after a native selection edit. Cancellation (no edit) does not call it.
        case textSelection(start: Expression, end: Expression, action: String)
        /// Marks the receiver as a drag source. `kind` is a closed ASCII identifier (lowercase letters,
        /// digits and `_`, starting with a letter); `value` is a typed String expression owned by app
        /// state or model. No URI, no object reference, no clipboard read.
        case dragPayload(kind: String, value: Expression)
        /// Marks the receiver as a drop target for the named kind. `action` names a synchronous model
        /// method with signature `(kind: String, payload: String)`. The platform calls it only when a
        /// non-empty payload of the matching kind is dropped; empty payloads and foreign kinds are
        /// rejected by the generated wrapper without invoking the action.
        case dropTarget(kind: String, action: String)
    }

    public let operation: Operation
    public let location: SourceLocation?

    public init(operation: Operation, location: SourceLocation? = nil) {
        self.operation = operation
        self.location = location
    }
}

/// Build-time selection only. No branch discriminator is emitted to a target application.
public struct PlatformAlternatives<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public let ios: Value
    public let android: Value
    public let harmonyOS: Value

    public init(ios: Value, android: Value, harmonyOS: Value) {
        self.ios = ios
        self.android = android
        self.harmonyOS = harmonyOS
    }

    public func value(for platform: TargetPlatform) -> Value {
        switch platform {
        case .ios: ios
        case .android: android
        case .harmonyOS: harmonyOS
        }
    }
}

public enum TargetPlatform: String, Codable, Sendable {
    case ios, android, harmonyOS
}
