/// A named, synchronous action exposed through the platform accessibility action list.
/// The label remains a typed localized/dynamic text value, never a hardcoded native string.
public struct AccessibilityCustomAction: Codable, Equatable, Sendable {
    public let label: Expression
    public let action: StateAction

    public init(label: Expression, action: StateAction) {
        self.label = label
        self.action = action
    }
}

/// A parent-declared sequence of direct children, independent of their drawing order.
public struct AccessibilityTraversal: Codable, Equatable, Sendable {
    public struct Step: Codable, Equatable, Sendable {
        public let name: String
        public let after: String?

        public init(name: String, after: String? = nil) {
            self.name = name
            self.after = after
        }
    }

    public let steps: [Step]

    public init(steps: [Step]) {
        self.steps = steps
    }
}
