import RefractIR

/// Typed values only. Neither target receives a URL-opening API or a URL parser.
public enum LinkHandoffEmission {
    public static func compose(_ destination: LinkDestination) -> String {
        "LinkDestination(kind = LinkDestination.Kind.\(destination.kind == .external ? "EXTERNAL" : "DEEP_LINK"), scheme = \"\(destination.scheme)\", host = \"\(destination.host)\", path = \"\(destination.path)\")"
    }

    public static func compose(_ policy: LinkPolicy) -> String {
        let entries = policy.allowed.map {
            "LinkAllowlistEntry(scheme = \"\($0.scheme)\", host = \"\($0.host)\")"
        }.joined(separator: ", ")
        return "LinkPolicy(allowed = listOf(\(entries)))"
    }

    public static func arkUI(_ destination: LinkDestination) -> String {
        "new LinkDestination('\(destination.kind.rawValue)', '\(destination.scheme)', '\(destination.host)', '\(destination.path)')"
    }

    public static func arkUI(_ policy: LinkPolicy) -> String {
        let entries = policy.allowed.map {
            "new LinkAllowlistEntry('\($0.scheme)', '\($0.host)')"
        }.joined(separator: ", ")
        return "new LinkPolicy([\(entries)])"
    }
}
