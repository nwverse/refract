public enum LocalizationKey {
    public static func isCanonical(_ key: String) -> Bool {
        let segments = key.split(separator: ".", omittingEmptySubsequences: false)
        return !segments.isEmpty && segments.allSatisfy { segment in
            guard let first = segment.first, first.isASCII, first.isLetter, first.isLowercase else { return false }
            return segment.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
        }
    }
}

extension Expression {
    public var isLocalizedText: Bool {
        if case .localizedText = value { return true }
        return false
    }
}

/// An immutable input used by a generated native component's public signature.
public struct ScreenParameter: Codable, Equatable, Sendable {
    public let name: String
    /// For an item input, the identity's scalar type; itemType carries the actual parameter type.
    public let type: ValueType
    public let enumName: String?
    public let itemType: String?
    public let isOptional: Bool
    public let location: SourceLocation?

    public init(name: String, type: ValueType, enumName: String? = nil, itemType: String? = nil, isOptional: Bool = false,
                location: SourceLocation? = nil) {
        self.name = name
        self.type = type
        self.enumName = enumName
        self.itemType = itemType
        self.isOptional = isOptional
        self.location = location
    }

    private enum CodingKeys: String, CodingKey { case name, type, enumName, itemType, isOptional, location }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        type = try values.decode(ValueType.self, forKey: .type)
        enumName = try values.decodeIfPresent(String.self, forKey: .enumName)
        itemType = try values.decodeIfPresent(String.self, forKey: .itemType)
        isOptional = try values.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
        location = try values.decodeIfPresent(SourceLocation.self, forKey: .location)
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
        case .revision: ""

        }
    }
}
