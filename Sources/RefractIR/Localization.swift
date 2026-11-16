public enum LocalizationKey {
    public static func isCanonical(_ key: String) -> Bool {
        let segments = key.split(separator: ".", omittingEmptySubsequences: false)
        return !segments.isEmpty && segments.allSatisfy { segment in
            guard let first = segment.first, first.isASCII, first.isLetter, first.isLowercase else { return false }
            return segment.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
        }
    }
}

/// An immutable input used by a generated native component's public signature.
public struct ScreenParameter: Codable, Equatable, Sendable {
    public let name: String
    public let type: ValueType
    public let location: SourceLocation?

    public init(name: String, type: ValueType, location: SourceLocation? = nil) {
        self.name = name
        self.type = type
        self.location = location
    }
}

/// A user-facing string whose lookup key and ordered interpolation values are known at build time.
public struct LocalizedText: Codable, Equatable, Sendable {
    public let key: String
    public let arguments: [Expression]

    public init(key: String, arguments: [Expression] = []) {
        self.key = key
        self.arguments = arguments
    }
}

extension ValueType {
    public init?(frontendName: String) {
        switch frontendName {
        case "String": self = .string
        case "Int": self = .int
        case "Double": self = .double
        case "Bool": self = .bool
        default: return nil
        }
    }

    public var formatSpecifier: String {
        switch self {
        case .string: "s"
        case .int: "d"
        case .double: "f"
        case .bool: ""
        }
    }
}
