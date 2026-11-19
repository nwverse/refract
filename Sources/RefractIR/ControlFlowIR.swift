/// A locally declared finite enum with no raw value or inheritance. Each case has at most one scalar payload.
public struct EnumDeclaration: Codable, Equatable, Sendable {
    public var name: String {
        kind?.stateTypeName ?? explicitName
    }

    private let explicitName: String
    public let cases: [String]
    public let payloadTypes: [String: ValueType]
    public let isNavigationDestination: Bool
    public let nativeValueKind: NativeValueKind?
    public var kind: NativeValueKind? { nativeValueKind }
    public let location: SourceLocation?

    public init(name: String, cases: [String], payloadTypes: [String: ValueType] = [:],
                isNavigationDestination: Bool = false, nativeValueKind: NativeValueKind? = nil,
                location: SourceLocation? = nil) {
        self.explicitName = name
        self.cases = cases
        self.payloadTypes = payloadTypes
        self.isNavigationDestination = isNavigationDestination
        self.nativeValueKind = nativeValueKind
        self.location = location
    }

    private enum CodingKeys: String, CodingKey { case name, cases, payloadTypes, isNavigationDestination, nativeValueKind, location }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(name, forKey: .name)
        try values.encode(cases, forKey: .cases)
        try values.encode(payloadTypes, forKey: .payloadTypes)
        try values.encode(isNavigationDestination, forKey: .isNavigationDestination)
        try values.encodeIfPresent(nativeValueKind, forKey: .nativeValueKind)
        try values.encodeIfPresent(location, forKey: .location)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        explicitName = try values.decode(String.self, forKey: .name)
        cases = try values.decode([String].self, forKey: .cases)
        payloadTypes = try values.decodeIfPresent([String: ValueType].self, forKey: .payloadTypes) ?? [:]
        isNavigationDestination = try values.decodeIfPresent(Bool.self, forKey: .isNavigationDestination) ?? false
        nativeValueKind = try values.decodeIfPresent(NativeValueKind.self, forKey: .nativeValueKind)
        location = try values.decodeIfPresent(SourceLocation.self, forKey: .location)
    }
}

public struct SwitchCase: Codable, Equatable, Sendable {
    public let name: String
    public let binding: String?
    public let children: [ViewNode]

    public init(name: String, binding: String? = nil, children: [ViewNode]) {
        self.name = name
        self.binding = binding
        self.children = children
    }

    private enum CodingKeys: String, CodingKey { case name, binding, children }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        binding = try values.decodeIfPresent(String.self, forKey: .binding)
        children = try values.decode([ViewNode].self, forKey: .children)
    }
}
