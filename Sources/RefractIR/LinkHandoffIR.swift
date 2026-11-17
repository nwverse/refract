/// A bounded destination. Paths are data, not URL templates or executable platform code.
public struct LinkDestination: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case external, deepLink }

    public let kind: Kind
    public let scheme: String
    public let host: String
    public let path: String

    public init(kind: Kind, scheme: String, host: String, path: String) {
        self.kind = kind
        self.scheme = scheme
        self.host = host
        self.path = path
    }
}

public struct LinkAllowlistEntry: Codable, Equatable, Sendable {
    public let scheme: String
    public let host: String

    public init(scheme: String, host: String) {
        self.scheme = scheme
        self.host = host
    }
}

public struct LinkPolicy: Codable, Equatable, Sendable {
    public let allowed: [LinkAllowlistEntry]

    public init(allowed: [LinkAllowlistEntry]) {
        self.allowed = allowed
    }

    public func permits(_ destination: LinkDestination) -> Bool {
        allowed.contains { $0.scheme == destination.scheme && $0.host == destination.host }
    }
}

/// This declaration has no URL parser: a closed source constructor supplies a validated value.
public enum LinkHandoffIR {
    public static let sourcePrelude = """
    public struct RefractLinkDestination: Equatable, Sendable {
        public enum Kind: Sendable { case external, deepLink }
        public let kind: Kind
        public let scheme: String
        public let host: String
        public let path: String

        public static func https(host: String, path: String) -> Self {
            Self(kind: .external, scheme: "https", host: host, path: path)
        }

        public static func deepLink(scheme: String, host: String, path: String) -> Self {
            Self(kind: .deepLink, scheme: scheme, host: host, path: path)
        }
    }

    public struct RefractLinkPolicy: Sendable {
        public let allowed: [(scheme: String, host: String)]

        public init(allowed: [(scheme: String, host: String)]) {
            self.allowed = allowed
        }

        public func permits(_ destination: RefractLinkDestination) -> Bool {
            allowed.contains { $0.scheme == destination.scheme && $0.host == destination.host }
        }
    }

    public enum RefractLinkHandoffResult: Sendable {
        case handedOff, cancelled, disallowed, unsupportedScheme, unavailable
    }

    public protocol RefractLinkHandoff {
        func begin(_ destination: RefractLinkDestination,
                   completion: @escaping (RefractLinkHandoffResult) -> Void)
        func cancel(_ destination: RefractLinkDestination)
    }
    """
}
