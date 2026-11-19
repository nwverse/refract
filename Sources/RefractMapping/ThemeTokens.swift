import RefractIR

/// An application-owned native symbol, or the explicitly declared interaction-state resolver for a color token.
/// No resource contents or state defaults are synthesized by Refract.
public enum TokenMapping: Codable, Equatable, Sendable, ExpressibleByStringLiteral {
    case symbol(String)
    case interaction(InteractionTokenMapping)

    public init(_ symbol: String) { self = .symbol(symbol) }

    public init(stringLiteral value: String) { self = .symbol(value) }

    public init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer()
        if let symbol = try? values.decode(String.self) {
            self = .symbol(symbol)
        } else {
            self = .interaction(try values.decode(InteractionTokenMapping.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.singleValueContainer()
        switch self {
        case let .symbol(symbol): try values.encode(symbol)
        case let .interaction(mapping): try values.encode(mapping)
        }
    }

    public var symbol: String? {
        guard case let .symbol(value) = self else { return nil }
        return value
    }

    public func compose(location: SourceLocation?) throws -> String {
        guard let symbol else {
            throw Diagnostic(code: "interactionToken",
                message: "An interaction color token requires explicit enabled, pressed and focused values.",
                suggestion: "Use `refractInteractionColor(token, enabled: ..., pressed: ..., focused: ...)`.",
                location: location)
        }
        return symbol
    }

    public func compose(enabled: String, pressed: String, focused: String,
                        mapping: Mapping, location: SourceLocation?) throws -> String {
        guard case let .interaction(token) = self else {
            throw Diagnostic(code: "interactionToken",
                message: "Token `\(symbol ?? "unknown")` has no interaction-state mapping.",
                suggestion: "Declare the application resolver and all four state resource references.",
                location: location)
        }
        return try render(token, mapping: mapping, platform: .android, enabled: enabled, pressed: pressed, focused: focused)
    }

    public func arkUI(enabled: String, pressed: String, focused: String,
                      mapping: Mapping, location: SourceLocation?) throws -> String {
        guard case let .interaction(token) = self else {
            throw Diagnostic(code: "interactionToken",
                message: "Token `\(symbol ?? "unknown")` has no interaction-state mapping.",
                suggestion: "Declare the application resolver and all four state resource references.",
                location: location)
        }
        return try render(token, mapping: mapping, platform: .harmonyOS, enabled: enabled, pressed: pressed, focused: focused)
    }

    private func render(_ token: InteractionTokenMapping, mapping: Mapping, platform: Platform,
                        enabled: String, pressed: String, focused: String) throws -> String {
        let values = try token.states.map { state in
            switch (state, platform) {
            case let (.symbol(symbol), _): return symbol
            case let (.resource(name), .android):
                guard let className = mapping.android.resources.className else {
                    throw Diagnostic(code: "mappingResource", message: "Android color resources need an R class.",
                        suggestion: "Declare android.resources.className.")
                }
                let qualifier = className == "\(mapping.android.output.packageName ?? "").R" ? "R" : className
                return "\(qualifier).color.\(name)"
            case let (.resource(name), .harmonyOS):
                guard let namespace = mapping.harmonyOS.resources.namespace else {
                    throw Diagnostic(code: "mappingResource", message: "HarmonyOS color resources need a namespace.",
                        suggestion: "Declare harmonyOS.resources.namespace.")
                }
                return "$r('\(namespace).color.\(name)')"
            }
        }
        return "\(token.resolver)(\(enabled), \(pressed), \(focused), \(values.joined(separator: ", ")))"
    }

    public func interactionImports(mapping: Mapping, platform: Platform) throws -> (resolver: String, resourceClass: String?) {
        guard case let .interaction(token) = self else {
            throw Diagnostic(code: "interactionToken", message: "The token has no interaction-state mapping.",
                suggestion: "Use `refractInteractionColor` only with a declared interaction token.")
        }
        let owner = token.resolver.split(separator: ".").dropLast().last.map(String.init) ?? token.resolver
        return (owner, platform == .android && token.states.contains(where: {
            if case .resource = $0 { return true }
            return false
        }) ? mapping.android.resources.className : nil)
    }

    /// Both the resolver and resource owner must be explicitly imported by the app mapping.
    public var importSymbol: String? {
        switch self {
        case let .symbol(symbol): symbol.split(separator: ".").first.map(String.init)
        case .interaction: nil
        }
    }
}

public struct InteractionTokenMapping: Codable, Equatable, Sendable {
    public let resolver: String
    public let normal: NativeThemeValue
    public let disabled: NativeThemeValue
    public let pressed: NativeThemeValue
    public let focused: NativeThemeValue

    public init(resolver: String, normal: NativeThemeValue, disabled: NativeThemeValue,
                pressed: NativeThemeValue, focused: NativeThemeValue) {
        self.resolver = resolver
        self.normal = normal
        self.disabled = disabled
        self.pressed = pressed
        self.focused = focused
    }

    var states: [NativeThemeValue] { [normal, pressed, focused, disabled] }
}

public enum NativeThemeValue: Codable, Equatable, Sendable, ExpressibleByStringLiteral {
    case symbol(String)
    case resource(String)

    public init(stringLiteral value: String) { self = .symbol(value) }

    public init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer()
        if let symbol = try? values.decode(String.self) {
            self = .symbol(symbol)
            return
        }
        let resource = try values.decode([String: String].self)
        guard let name = resource["resource"], resource.count == 1 else {
            throw DecodingError.dataCorruptedError(in: values, debugDescription: "Expected one resource name.")
        }
        self = .resource(name)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.singleValueContainer()
        switch self {
        case let .symbol(symbol): try values.encode(symbol)
        case let .resource(name): try values.encode(["resource": name])
        }
    }
}
