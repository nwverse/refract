import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import RefractIR

/// A build-time resource reference. File registration and parsing stay in the consuming app.
public enum AssetKind: String, CaseIterable, Codable, Sendable {
    case image, font, raw
}

/// Generator-only metadata; no asset bytes or open file handles cross this boundary.
public struct AssetVariant: Equatable, Sendable {
    public let qualifier: String
    public let fileName: String
    public let byteCount: UInt64

    public init(qualifier: String, fileName: String, byteCount: UInt64) {
        self.qualifier = qualifier
        self.fileName = fileName
        self.byteCount = byteCount
    }
}

public enum AssetCatalog {
    /// Resource policy, not an arbitrary byte limit: large image dimensions and raw decoding are app-owned.
    public static let maximumBytes: UInt64 = 16 * 1024 * 1024

    public static func resolve(_ name: String, kind: AssetKind, mapping: Mapping,
                               platform: Platform, location: SourceLocation? = nil) throws -> [AssetVariant] {
        guard isResourceName(name) else {
            throw failure("invalid_name", kind: kind, platform: platform,
                          message: "Asset `\(name)` is not a lowercase resource identifier.",
                          suggestion: "Use a lowercase ASCII letter followed by lowercase letters, digits or underscores", location: location)
        }
        let configuration = mapping.platform(platform).resources
        guard configuration.assetCatalog != nil else {
            throw failure("not_configured", kind: kind, platform: platform,
                          message: "The \(platform.displayName) \(kind.rawValue) asset catalog is not configured.",
                          suggestion: "Set `resources.assetCatalog` to \(platform == .android ? "`res`" : "`resources`") and declare base assets in the application catalog", location: location)
        }
        if platform == .harmonyOS, configuration.namespace != "app" {
            throw failure("namespace", kind: kind, platform: platform,
                          message: "Asset references require the HarmonyOS `app` namespace, not `\(configuration.namespace ?? "missing")`.",
                          suggestion: "Use the consuming application's `app` namespace", location: location)
        }
        guard let base = mapping.resourceBaseURL else {
            throw failure("not_configured", kind: kind, platform: platform,
                          message: "The asset catalog has no resolved mapping directory.",
                          suggestion: "Load refract.json by path or provide its resource base explicitly", location: location)
        }
        guard let directory = configuration.assetCatalog,
              let root = boundedRoot(directory, base: base, platform: platform, kind: kind, location: location) else {
            throw failure("not_configured", kind: kind, platform: platform,
                          message: "The asset catalog root is unavailable or unsafe.",
                          suggestion: "Provide a real, non-symbolic application resource directory", location: location)
        }
        let expected = qualifierDirectories(platform: platform, kind: kind)
        var variants: [String: AssetVariant] = [:]
        for (qualifier, suffixes) in expected {
            let directoryURL = root.appendingPathComponent(suffixes.directory, isDirectory: true)
            guard let entries = entries(in: directoryURL, kind: kind, platform: platform, location: location) else { continue }
            var matching: [AssetVariant] = []
            for entry in entries {
                let file = directoryURL.appendingPathComponent(entry, isDirectory: false)
                guard let metadata = regularFile(file, kind: kind, platform: platform, location: location) else { continue }
                guard entry.hasPrefix(name + ".") else { continue }
                let suffix = String(entry.dropFirst(name.count + 1))
                guard suffix.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber) }) else {
                    throw failure("invalid_extension", kind: kind, platform: platform,
                                  message: "Asset `\(entry)` needs a lowercase alphanumeric extension.",
                                  suggestion: "Use a consistent lowercase file extension in every catalog", location: location)
                }
                guard suffixes.extensions.contains(suffix) else {
                    throw failure("type_mismatch", kind: kind, platform: platform,
                                  message: "Asset `\(name)` has `.\(suffix)` in the \(qualifier) \(kind.rawValue) directory; expected \(suffixes.extensions.joined(separator: " or ")).",
                                  suggestion: "Use one supported extension in every qualified catalog", location: location)
                }
                if platform == .android, kind == .image, suffix == "xml" {
                    try validateVectorDrawable(file, location: location)
                }
                matching.append(AssetVariant(qualifier: qualifier, fileName: entry, byteCount: metadata.size))
            }
            guard matching.count <= 1 else {
                throw failure("ambiguous", kind: kind, platform: platform,
                              message: "Asset `\(name)` has multiple files in the \(platform.displayName) \(qualifier) catalog.",
                              suggestion: "Keep exactly one supported file for each resource and qualifier", location: location)
            }
            if let variant = matching.first { variants[qualifier] = variant }
        }
        guard let baseVariant = variants["base"] else {
            throw failure("missing_base", kind: kind, platform: platform,
                          message: "Asset `\(name)` has no base \(kind.rawValue) resource on \(platform.displayName).",
                          suggestion: "Add `\(name)` to \(expected["base"]!.directory), then provide the same qualifiers on both platforms", location: location)
        }
        if kind == .raw, variants.count != 1 {
            throw failure("raw_qualified", kind: kind, platform: platform,
                          message: "Raw asset `\(name)` must be a single unqualified resource on \(platform.displayName).",
                          suggestion: "Raw resources have no portable qualified-resource semantics; keep one base file", location: location)
        }
        let limits = maximumBytes(for: kind)
        for variant in variants.values where variant.byteCount == 0 || variant.byteCount > limits {
            throw failure("size", kind: kind, platform: platform,
                          message: "Asset `\(variant.fileName)` is empty or exceeds the \(limits)-byte catalog limit.",
                          suggestion: "Package a nonempty, bounded asset; content-specific decoding limits remain app-owned", location: location)
        }
        return [baseVariant] + variants.filter { $0.key != "base" }.sorted { $0.key < $1.key }.map(\.value)
    }

    public static func resolveBoth(_ name: String, kind: AssetKind, mapping: Mapping,
                                   location: SourceLocation? = nil) throws {
        let android = try resolve(name, kind: kind, mapping: mapping, platform: .android, location: location)
        let harmony = try resolve(name, kind: kind, mapping: mapping, platform: .harmonyOS, location: location)
        if kind == .raw, android.first?.fileName != harmony.first?.fileName {
            throw Diagnostic(code: "R.asset.raw_extension",
                message: "Raw asset `\(name)` has different file names on Android and HarmonyOS.",
                suggestion: "Use the same lowercase base name and alphanumeric extension in both raw catalogs", location: location)
        }
        guard Set(android.map(\.qualifier)) == Set(harmony.map(\.qualifier)) else {
            throw Diagnostic(code: "R.asset.qualifier_parity",
                message: "Asset `\(name)` has different qualifiers on Android and HarmonyOS.",
                suggestion: "Provide equivalent base, dark and density variants in both native catalogs", location: location)
        }
    }

    public static func isResourceName(_ name: String) -> Bool {
        guard let first = name.first, first.isASCII, first.isLowercase else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
    }

    public static func rawExtension(_ name: String, variants: [AssetVariant]) throws -> String {
        guard let fileName = variants.first?.fileName, let suffix = fileName.split(separator: ".").last,
              suffix.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber) }) else {
            throw Diagnostic(code: "R.asset.raw_extension", message: "Raw asset `\(name)` needs a safe file extension.",
                             suggestion: "Use a lowercase alphanumeric extension in both raw catalogs")
        }
        return String(suffix)
    }

    private static func maximumBytes(for kind: AssetKind) -> UInt64 {
        kind == .font ? 4 * 1024 * 1024 : maximumBytes
    }

    private static func boundedRoot(_ path: String, base: URL, platform: Platform,
                                    kind: AssetKind, location: SourceLocation?) -> URL? {
        guard path == (platform == .android ? "res" : "resources") else { return nil }
        let root = base.appendingPathComponent(path, isDirectory: true).standardizedFileURL
        guard root.deletingLastPathComponent().path == base.path,
              isDirectory(root, followLinks: false) else { return nil }
        return root
    }

    private static func qualifierDirectories(platform: Platform, kind: AssetKind) -> [String: (directory: String, extensions: Set<String>)] {
        func directory(_ qualifier: String, _ folder: String) -> (directory: String, extensions: Set<String>) {
            switch (platform, kind) {
            case (.android, .image):
                return (folder.isEmpty ? "drawable" : "drawable-\(folder)", ["png", "jpg", "jpeg", "webp", "gif", "xml"])
            case (.harmonyOS, .image):
                return ((folder.isEmpty ? "base" : folder) + "/media", ["png", "jpg", "jpeg", "webp", "gif", "svg", "bmp"])
            case (.android, .font): return ("font", ["ttf", "otf"])
            case (.harmonyOS, .font): return ("rawfile", ["ttf", "otf"])
            case (.android, .raw): return ("raw", ["json", "txt", "bin", "svg", "pdf"])
            case (.harmonyOS, .raw): return ("rawfile", ["json", "txt", "bin", "svg", "pdf"])
            }
        }
        if kind != .image { return ["base": directory("base", "")] }
        if platform == .harmonyOS {
            return [
                "base": directory("base", ""),
                "dark": directory("dark", "dark"),
                "density-ldpi": directory("density-ldpi", "ldpi"),
                "density-mdpi": directory("density-mdpi", "mdpi"),
                "density-hdpi": directory("density-hdpi", "xldpi"),
                "density-xhdpi": directory("density-xhdpi", "xxldpi"),
                "density-xxhdpi": directory("density-xxhdpi", "xxxldpi"),
            ]
        }
        return [
            "base": directory("base", ""),
            "dark": directory("dark", "night"),
            "density-ldpi": directory("density-ldpi", "ldpi"),
            "density-mdpi": directory("density-mdpi", "mdpi"),
            "density-hdpi": directory("density-hdpi", "hdpi"),
            "density-xhdpi": directory("density-xhdpi", "xhdpi"),
            "density-xxhdpi": directory("density-xxhdpi", "xxhdpi"),
        ]
    }

    private static func entries(in directory: URL, kind: AssetKind, platform: Platform,
                                location: SourceLocation?) -> [String]? {
        guard isDirectory(directory, followLinks: false) else { return nil }
        do {
            let values = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            return values.filter { !$0.hasPrefix(".") }.sorted()
        } catch {
            return nil
        }
    }

    private static func regularFile(_ url: URL, kind: AssetKind, platform: Platform,
                                    location: SourceLocation?) -> (name: String, size: UInt64)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular,
              let number = attributes[.size] as? NSNumber else { return nil }
        return (url.lastPathComponent, number.uint64Value)
    }

    private static func isDirectory(_ url: URL, followLinks: Bool) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType else { return false }
        return type == .typeDirectory
    }

    private static func validateVectorDrawable(_ url: URL, location: SourceLocation?) throws {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            let delegate = VectorRootDelegate()
            parser.delegate = delegate
            guard parser.parse(), delegate.root == "vector" else {
                throw failure("invalid_drawable", kind: .image, platform: .android,
                              message: "Android drawable `\(url.lastPathComponent)` is not a supported VectorDrawable.",
                              suggestion: "Use a root <vector> drawable, or a native raster image supported by Compose", location: location)
            }
        } catch let error as Diagnostic {
            throw error
        } catch {
            throw failure("invalid_drawable", kind: .image, platform: .android,
                          message: "Android drawable `\(url.lastPathComponent)` cannot be read as XML.",
                          suggestion: "Provide a well-formed app-owned VectorDrawable without external entities", location: location)
        }
    }

    private static func failure(_ reason: String, kind: AssetKind, platform: Platform,
                                message: String, suggestion: String, location: SourceLocation?) -> Diagnostic {
        Diagnostic(code: "R.asset.\(reason)", message: message, suggestion: suggestion, location: location)
    }
}

private final class VectorRootDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    var root: String?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if root == nil { root = elementName }
    }
}
