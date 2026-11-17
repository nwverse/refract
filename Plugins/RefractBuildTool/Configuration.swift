import Foundation
import PackagePlugin

struct ConsumerConfiguration: Decodable {
    let schemaVersion: Int
    let target: String
    let sources: [String]
    let mapping: String?
    let androidOutput: String
    let harmonyOutput: String
    let resourceInputs: [String]
    var package: URL

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, target, sources, mapping, androidOutput, harmonyOutput, resourceInputs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        target = try values.decode(String.self, forKey: .target)
        sources = try values.decode([String].self, forKey: .sources)
        mapping = try values.decodeIfPresent(String.self, forKey: .mapping)
        androidOutput = try values.decode(String.self, forKey: .androidOutput)
        harmonyOutput = try values.decode(String.self, forKey: .harmonyOutput)
        resourceInputs = try values.decodeIfPresent([String].self, forKey: .resourceInputs) ?? []
        package = URL(fileURLWithPath: "/")
    }

    static func load(url: URL, package: URL, target: String) throws -> ConsumerConfiguration {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw PluginError(message: "Cannot read package-root refract-swiftpm.json: \(error)") }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw PluginError(message: "Invalid refract-swiftpm.json: \(error)") }
        guard let object = object as? [String: Any],
              Set(object.keys).isSubset(of: ["schemaVersion", "target", "sources", "mapping",
                                             "androidOutput", "harmonyOutput", "resourceInputs"]) else {
            throw PluginError(message: "refract-swiftpm.json must be an object with only its documented fields.")
        }
        let decoded: ConsumerConfiguration
        do { decoded = try JSONDecoder().decode(ConsumerConfiguration.self, from: data) }
        catch { throw PluginError(message: "Invalid refract-swiftpm.json: \(error)") }
        var configuration = decoded
        configuration.package = package
        guard configuration.schemaVersion == 1, configuration.target == target,
              !configuration.sources.isEmpty, configuration.sources.count == Set(configuration.sources).count else {
            throw PluginError(message: "Configuration requires schemaVersion 1, the selected target, and unique nonempty sources.")
        }
        var basenames = Set<String>()
        for source in configuration.sources {
            let name = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
            guard URL(fileURLWithPath: source).pathExtension == "swift", !name.isEmpty,
                  basenames.insert(name).inserted else {
                throw PluginError(message: "Inputs must be Swift files with unique, nonempty base filenames.")
            }
        }
        _ = try configuration.resolve(configuration.androidOutput, description: "Android output")
        _ = try configuration.resolve(configuration.harmonyOutput, description: "HarmonyOS output")
        return configuration
    }

    func resolve(_ path: String, description: String) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else {
            throw PluginError(message: "Use a package-relative POSIX path for \(description): \(path).")
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ $0 != "." && $0 != ".." && !$0.isEmpty }) else {
            throw PluginError(message: "Unsafe or empty path component for \(description): \(path).")
        }
        let url = components.reduce(package) { $0.appendingPathComponent(String($1)) }
        let packagePath = package.resolvingSymlinksInPath().path
        let resolvedPath = url.resolvingSymlinksInPath().path
        guard resolvedPath.hasPrefix(packagePath + "/") else {
            throw PluginError(message: "\(description) resolves outside the consuming package: \(path).")
        }
        var ancestor = url
        while ancestor.path != package.path, ancestor.path != "/" {
            let values = try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw PluginError(message: "\(description) must not traverse a symbolic link: \(path).")
            }
            ancestor.deleteLastPathComponent()
        }
        guard description.contains("output") || FileManager.default.fileExists(atPath: url.path) else {
            throw PluginError(message: "Missing \(description): \(path).")
        }
        return url
    }

    func mappingCatalogs() throws -> [URL] {
        guard let mapping else { return [] }
        let mappingURL = try resolve(mapping, description: "mapping")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: mappingURL)) as? [String: Any]
        guard let object else { throw PluginError(message: "The mapping root must be an object.") }
        return try ["android", "harmonyOS"].compactMap { platform in
            guard let resources = (object[platform] as? [String: Any])?["resources"] as? [String: Any],
                  let catalog = resources["catalog"] as? String else { return nil }
            let mappingDirectory = mappingURL.deletingLastPathComponent()
            guard !catalog.isEmpty, !catalog.hasPrefix("/"), !catalog.contains("\\"),
                  !catalog.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }) else {
                throw PluginError(message: "Unsafe \(platform) resource catalog path: \(catalog).")
            }
            let url = catalog.split(separator: "/").reduce(mappingDirectory) {
                $0.appendingPathComponent(String($1))
            }
            guard url.path.hasPrefix(package.path + "/"),
                  url.resolvingSymlinksInPath().path.hasPrefix(package.resolvingSymlinksInPath().path + "/") else {
                throw PluginError(message: "\(platform) resource catalog escapes the consuming package: \(catalog).")
            }
            var ancestor = url
            while ancestor.path != package.path, ancestor.path != "/" {
                if try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    throw PluginError(message: "Resource catalogs must not traverse symbolic links: \(catalog).")
                }
                ancestor.deleteLastPathComponent()
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PluginError(message: "Missing \(platform) resource catalog: \(catalog).")
            }
            return url
        }
    }

    var committedOutputs: [URL] {
        sources.flatMap { source in
            let basename = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
            return [androidOutput + "/" + basename + ".kt", harmonyOutput + "/" + basename + ".ets"]
        }.compactMap { try? resolve($0, description: "committed output") }
    }
}

struct PluginError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
