import Foundation
import RefractIR
import SwiftSyntax

/// Parses only closed literal constructors. It never accepts a URL string or evaluates a destination.
struct LinkHandoffFrontend {
    unowned let builder: Builder

    func destination(_ expression: ExprSyntax) -> NativeArgument? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.base?.trimmedDescription == "RefractLinkDestination" else {
            return rejected(expression, "A link destination must use a closed `RefractLinkDestination` constructor.",
                            "Use `.https(host:path:)` or `.deepLink(scheme:host:path:)` with literal bounded values.")
        }
        let name = member.declName.baseName.text
        let labels = call.arguments.map { $0.label?.text ?? "" }
        guard (name == "https" && labels == ["host", "path"])
                || (name == "deepLink" && labels == ["scheme", "host", "path"]),
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else {
            return rejected(ExprSyntax(call), "Link destination constructor `\(name)` is outside the bounded source contract.",
                            "Use `RefractLinkDestination.https(host:path:)` or `.deepLink(scheme:host:path:)`.")
        }
        var values: [String: String] = [:]
        for argument in call.arguments {
            guard let label = argument.label?.text, let value = literal(argument.expression) else {
                return rejected(argument.expression, "Link destination fields must be plain string literals.",
                                "Use a static path with no interpolation, interpolation segments or computed values.")
            }
            values[label] = value
        }
        guard let host = values["host"], let path = values["path"] else { return nil }
        let scheme = name == "https" ? "https" : values["scheme"] ?? ""
        let kind: LinkDestination.Kind = name == "https" ? .external : .deepLink
        if kind == .deepLink && scheme == "https" {
            builder.error("RFLINK002", "A deep link cannot use the external HTTPS constructor scheme.",
                          "Use `.https(host:path:)` for an external link or a custom lowercase deep-link scheme.", at: expression)
            return nil
        }
        guard validateScheme(scheme, at: expression),
              validateHost(host, at: expression), validatePath(path, at: expression) else { return nil }
        return NativeArgument(label: "destination",
            expression: Expression(.linkDestination(LinkDestination(kind: kind, scheme: scheme, host: host, path: path)),
                                   type: nil, location: builder.location(of: expression)),
            type: .linkDestination, location: builder.location(of: expression))
    }

    func policy(_ expression: ExprSyntax) -> NativeArgument? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.trimmedDescription == "RefractLinkPolicy",
              call.arguments.count == 1, call.arguments.first?.label?.text == "allowed",
              let array = call.arguments.first?.expression.as(ArrayExprSyntax.self),
              !array.elements.isEmpty, array.elements.count <= 16 else {
            return rejected(expression, "A link policy requires one nonempty literal allowlist with at most 16 entries.",
                            "Use `RefractLinkPolicy(allowed: [(scheme: \"https\", host: \"docs.example.test\")])`.")
        }
        var entries: [LinkAllowlistEntry] = []
        for element in array.elements {
            guard let tuple = element.expression.as(TupleExprSyntax.self), tuple.elements.count == 2,
                  tuple.elements.first?.label?.text == "scheme", tuple.elements.last?.label?.text == "host",
                  let scheme = literal(tuple.elements.first!.expression),
                  let host = literal(tuple.elements.last!.expression) else {
                return rejected(element.expression, "Each allowlist entry must have exact literal `scheme` and `host` fields.",
                                "Do not use wildcards, suffixes, credentials, ports or computed policy values.")
            }
            guard validateScheme(scheme, at: element.expression), validateHost(host, at: element.expression) else {
                return nil
            }
            let entry = LinkAllowlistEntry(scheme: scheme, host: host)
            guard !entries.contains(entry) else {
                return rejected(element.expression, "The link allowlist contains a duplicate scheme/host pair.",
                                "Keep each exact scheme and host combination once.")
            }
            entries.append(entry)
        }
        return NativeArgument(label: "policy",
            expression: Expression(.linkPolicy(LinkPolicy(allowed: entries)), type: nil,
                                   location: builder.location(of: expression)),
            type: .linkPolicy, location: builder.location(of: expression))
    }

    func handoff(_ expression: ExprSyntax) -> NativeArgument? {
        guard let reference = expression.as(DeclReferenceExprSyntax.self),
              builder.parameters.contains(where: {
                  $0.name == reference.baseName.text && $0.itemType == "RefractLinkHandoff"
              }) else {
            return rejected(expression, "A link handoff must be an explicitly injected `RefractLinkHandoff` screen input.",
                            "Declare `let handoff: RefractLinkHandoff` and pass `handoff` without constructing or dispatching it.")
        }
        return NativeArgument(label: "handoff", expression: Expression(.reference(reference.baseName.text)),
                              type: .linkHandoff, location: builder.location(of: expression))
    }

    func validate(_ component: NativeComponent, declaration: NativeDeclaration) -> [Diagnostic] {
        guard declaration.parameters.map(\.type) == [.linkDestination, .linkPolicy, .linkHandoff] else {
            return [Diagnostic(code: "RFLINK001",
                message: "Link handoff component `\(declaration.name)` must expose exactly destination, policy and handoff inputs.",
                suggestion: "Use `let destination: RefractLinkDestination`, `let policy: RefractLinkPolicy`, and `let handoff: RefractLinkHandoff` in that order.",
                location: declaration.location)]
        }
        guard let destination = component.arguments.first,
              case let .linkDestination(value) = destination.expression?.value,
              let policyArgument = component.arguments.last(where: { $0.type == .linkPolicy }),
              case let .linkPolicy(policy) = policyArgument.expression?.value,
              policy.permits(value) else {
            return [Diagnostic(code: "RFLINK002",
                message: "Link handoff `\(declaration.name)` has a destination outside its exact scheme/host allowlist.",
                suggestion: "Add the exact pair to `RefractLinkPolicy` or remove the destination; never bypass the allowlist.",
                location: destinationLocation(component))]
        }
        return []
    }

    private func validateScheme(_ scheme: String, at expression: ExprSyntax) -> Bool {
        guard let first = scheme.utf8.first, first >= 0x61, first <= 0x7a,
              scheme.utf8.dropFirst().allSatisfy({
                  $0 >= 0x61 && $0 <= 0x7a || $0 >= 0x30 && $0 <= 0x39 || $0 == 0x2b || $0 == 0x2d || $0 == 0x2e
              }), scheme != "http", !["file", "content", "intent", "javascript", "data"].contains(scheme), scheme.count <= 32 else {
            builder.error("RFLINK002", "Link scheme `\(scheme)` is not a supported lowercase allowlisted scheme.",
                          "Use `https` or a bounded lowercase custom scheme; file, content, intent, javascript and data are rejected.", at: expression)
            return false
        }
        return true
    }

    private func validateHost(_ host: String, at expression: ExprSyntax) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.count <= 253, labels.count >= 2, labels.allSatisfy({ label in
            guard let first = label.first, let last = label.last,
                  first.isASCII, first.isLetter || first.isNumber,
                  last.isASCII, last.isLetter || last.isNumber else { return false }
            return label.count <= 63 && label.allSatisfy {
                $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-")
            }
        }) else {
            builder.error("RFLINK002", "Link host `\(host)` is not an exact lowercase DNS name.",
                          "Use an explicit lowercase host with at least two DNS labels; no wildcard, port, IP literal or credentials.", at: expression)
            return false
        }
        return true
    }

    private func validatePath(_ path: String, at expression: ExprSyntax) -> Bool {
        guard path.count <= 512, path == "/" || path.hasPrefix("/") && !path.hasSuffix("/") else {
            builder.error("RFLINK002", "Link path must be `/` or an absolute bounded path without a trailing slash.",
                          "Use literal static path segments with no query or fragment.", at: expression)
            return false
        }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")
        guard !path.contains("//"), !path.split(separator: "/").contains(".."),
              !path.split(separator: "/").contains("."), path.allSatisfy(allowed.contains) else {
            builder.error("RFLINK002", "Link path `\(path)` contains a traversal, ambiguous or non-ASCII segment.",
                          "Use static unreserved ASCII segments; keep query/fragment decoding in app-owned native code.", at: expression)
            return false
        }
        return true
    }

    private func literal(_ expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self), literal.segments.count == 1,
              case let .stringSegment(segment)? = literal.segments.first else { return nil }
        return segment.content.text
    }

    private func rejected(_ expression: ExprSyntax, _ message: String, _ suggestion: String) -> NativeArgument? {
        builder.error("RFLINK001", message, suggestion, at: expression)
        return nil
    }

    private func destinationLocation(_ component: NativeComponent) -> RefractIR.SourceLocation? {
        component.arguments.first(where: { $0.type == .linkDestination })?.location ?? component.arguments.first?.location
    }
}
