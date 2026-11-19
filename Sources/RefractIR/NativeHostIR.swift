/// Native host capabilities are closed contracts, not runtime services or target-source templates.
public enum NativeHostCapability: String, Codable, CaseIterable, Sendable {
    case lifecycle
    case notification
    case backgroundWork

    public var marker: String {
        switch self {
        case .lifecycle: "RefractLifecycleHost"
        case .notification: "RefractNotificationHost"
        case .backgroundWork: "RefractBackgroundWorkHost"
        }
    }

    /// Every request is correlated by a caller-visible id and revision. A return value cannot
    /// accidentally promise that permission, scheduling, delivery or background execution happened.
    public var actions: [String] {
        switch self {
        case .lifecycle: ["foreground", "background"]
        case .notification: ["present", "cancel", "confirm"]
        case .backgroundWork: ["schedule", "cancel", "confirm"]
        }
    }

    public var parameters: [ModelParameter] {
        switch self {
        case .lifecycle: []
        case .notification, .backgroundWork: [
            ModelParameter(externalName: nil, localName: "id", type: .string),
            ModelParameter(externalName: "revision", localName: "revision", type: .int),
        ]
        }
    }
}

public struct NativeHostContract: Codable, Equatable, Sendable {
    public let name: String
    public let capability: NativeHostCapability
    public let actions: [ModelAction]
    public let location: SourceLocation?

    public init(name: String, capability: NativeHostCapability, actions: [ModelAction] = [],
                location: SourceLocation? = nil) {
        self.name = name
        self.capability = capability
        self.actions = actions
        self.location = location
    }
}

public struct NativeHostReference: Codable, Equatable, Sendable {
    public let propertyName: String
    public let protocolName: String
    public let capability: NativeHostCapability

    public init(propertyName: String, protocolName: String, capability: NativeHostCapability) {
        self.propertyName = propertyName
        self.protocolName = protocolName
        self.capability = capability
    }
}

/// Reserved source declarations whose native representations are emitted beside the screen.
/// A host supplies the last known value; there is no hidden event stream or optional missing state.
public enum NativeValueKind: String, Codable, CaseIterable, Sendable {
    case scenePhase
    case notificationEvent
    case backgroundWorkEvent

    public var typeName: String {
        switch self {
        case .scenePhase: "RefractScenePhase"
        case .notificationEvent: "RefractNotificationEvent"
        case .backgroundWorkEvent: "RefractBackgroundWorkEvent"
        }
    }

    public var stateTypeName: String {
        switch self {
        case .scenePhase: "RefractScenePhase"
        case .notificationEvent: "RefractNotificationEventState"
        case .backgroundWorkEvent: "RefractBackgroundWorkEventState"
        }
    }

    public var states: [String] {
        switch self {
        case .scenePhase: ["foreground", "background"]
        case .notificationEvent: [
            "unavailable", "accepted", "scheduled", "delivered", "cancelled", "stale",
            "confirmationRequired", "confirmed",
        ]
        case .backgroundWorkEvent: [
            "unavailable", "accepted", "scheduled", "completed", "cancelled", "stale",
            "confirmationRequired", "confirmed",
        ]
        }
    }

    public var hasCorrelation: Bool { self != .scenePhase }

    public var correlationTypeName: String {
        switch self {
        case .scenePhase: "RefractScenePhase"
        case .notificationEvent: "RefractNotificationCorrelation"
        case .backgroundWorkEvent: "RefractBackgroundWorkCorrelation"
        }
    }

    public var declaration: EnumDeclaration {
        EnumDeclaration(name: self == .scenePhase ? typeName : stateTypeName, cases: states, nativeValueKind: self)
    }
}

public struct NativeValueReference: Codable, Equatable, Sendable {
    public let propertyName: String
    public let kind: NativeValueKind
    public let selectedField: NativeValueField

    public init(propertyName: String, kind: NativeValueKind, selectedField: NativeValueField) {
        self.propertyName = propertyName
        self.kind = kind
        self.selectedField = selectedField
    }
}

public enum NativeValueField: String, Codable, Sendable {
    case id
    case revision
    case state

    public var parameterName: String? {
        switch self {
        case .id: "id"
        case .revision: "revision"
        case .state: nil
        }
    }

    public var type: ValueType {
        switch self {
        case .id: .string
        case .revision: .int
        case .state: .string // Only a switch subject may use the event state.
        }
    }
}

public struct NativeValueProperty: Codable, Equatable, Sendable {
    public let value: String
    public let field: NativeValueField
    public init(value: String, field: NativeValueField) {
        self.value = value
        self.field = field
    }
}

/// These are screen-presence hooks. The host still owns application/scene foreground observation.
public struct NativeLifecycle: Codable, Equatable, Sendable {
    public let foreground: StateAction
    public let background: StateAction

    public init(foreground: StateAction, background: StateAction) {
        self.foreground = foreground
        self.background = background
    }
}
