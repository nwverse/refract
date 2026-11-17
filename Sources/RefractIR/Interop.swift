/// A typed parameter in a native component's Swift declaration or call.
public struct NativeParameter: Codable, Equatable, Sendable {
    public let label: String
    public let type: ValueType
    public let location: SourceLocation?

    public init(label: String, type: ValueType, location: SourceLocation? = nil) {
        self.label = label
        self.type = type
        self.location = location
    }
}

/// The source-owned signature. Its SwiftUI body remains the iOS implementation.
public struct NativeDeclaration: Codable, Equatable, Sendable {
    public let name: String
    public let parameters: [NativeParameter]
    public let location: SourceLocation?

    public init(name: String, parameters: [NativeParameter], location: SourceLocation? = nil) {
        self.name = name
        self.parameters = parameters
        self.location = location
    }
}

public struct NativeArgument: Codable, Equatable, Sendable {
    public let label: String
    public let expression: Expression
    public let type: ValueType?
    public let location: SourceLocation?

    public init(label: String, expression: Expression, type: ValueType?, location: SourceLocation? = nil) {
        self.label = label
        self.expression = expression
        self.type = type
        self.location = location
    }
}

/// A closed, typed native operation. There is deliberately no target-source payload.
public struct NativeModifier: Codable, Equatable, Sendable {
    public enum Operation: Codable, Equatable, Sendable {
        case testTag(Expression)
        case contentDescription(Expression)
        case retainCallback(identity: String)
        case contentType(String)
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
