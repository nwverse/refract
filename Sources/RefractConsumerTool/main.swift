import Foundation

struct Configuration: Decodable {
    let schemaVersion: Int
    let target: String
    let sources: [String]
    let mapping: String?
    let androidOutput: String
    let harmonyOutput: String
    let resourceInputs: [String]
}

struct Arguments {
    let mode: String
    let package: URL
    let target: String
    let work: URL?
    let explicitInputs: [String]?
    let mapping: String?
}

struct ConsumerError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("refract-swiftpm: \(message)\n").utf8))
    exit(1)
}

func parseArguments() throws -> Arguments {
    var mode: String?
    var package: String?
    var target: String?
    var work: String?
    var inputs: [String] = []
    var mapping: String?
    var index = 1
    while index < CommandLine.arguments.count {
        let argument = CommandLine.arguments[index]
        if !argument.hasPrefix("--"), mode == nil {
            mode = argument
            index += 1
            continue
        }
        guard ["--package", "--target", "--plugin-work", "--input", "--mapping", "--dependency"].contains(argument),
              index + 1 < CommandLine.arguments.count else {
            throw ConsumerError("Usage: RefractConsumerTool generate-and-check|check|publish --package <dir> --target <name> [--plugin-work <dir>]")
        }
        let value = CommandLine.arguments[index + 1]
        switch argument {
        case "--package": package = value
        case "--target": target = value
        case "--plugin-work": work = value
        case "--input": inputs.append(value)
        case "--dependency": break
        case "--mapping": mapping = value
        default: break
        }
        index += 2
    }
    guard let mode, ["generate-and-check", "check", "publish"].contains(mode), let package, let target else {
        throw ConsumerError("A valid mode, --package directory and --target name are required.")
    }
    return Arguments(mode: mode, package: URL(fileURLWithPath: package), target: target,
                     work: work.map { URL(fileURLWithPath: $0) },
                     explicitInputs: inputs.isEmpty ? nil : inputs, mapping: mapping)
}

func resolve(_ path: String, relativeTo directory: URL, description: String) throws -> URL {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else {
        throw ConsumerError("Use a package-relative POSIX path for \(description): \(path).")
    }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    guard components.allSatisfy({ $0 != "." && $0 != ".." && !$0.isEmpty }) else {
        throw ConsumerError("Unsafe or empty path component for \(description): \(path).")
    }
    let url = components.reduce(directory) { $0.appendingPathComponent(String($1)) }
    let root = directory.resolvingSymlinksInPath().path
    guard url.resolvingSymlinksInPath().path.hasPrefix(root + "/") else {
        throw ConsumerError("\(description) escapes the consuming package: \(path).")
    }
    var ancestor = url
    while ancestor.path != directory.path, ancestor.path != "/" {
        if try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw ConsumerError("\(description) must not traverse a symbolic link: \(path).")
        }
        ancestor.deleteLastPathComponent()
    }
    return url
}

func loadConfiguration(arguments: Arguments) throws -> (configuration: Configuration, inputs: [String]) {
    let url = arguments.package.appendingPathComponent("refract-swiftpm.json")
    let data = try Data(contentsOf: url)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let object, Set(object.keys).isSubset(of: ["schemaVersion", "target", "sources", "mapping",
                                                      "androidOutput", "harmonyOutput", "resourceInputs"]) else {
        throw ConsumerError("Configuration must be an object containing only documented fields.")
    }
    let configuration = try JSONDecoder().decode(Configuration.self, from: data)
    guard configuration.schemaVersion == 1, configuration.target == arguments.target,
          !configuration.sources.isEmpty, configuration.sources.count == Set(configuration.sources).count else {
        throw ConsumerError("Configuration requires schemaVersion 1, the selected target, and unique nonempty sources.")
    }
    var names = Set<String>()
    for source in configuration.sources {
        let url = try resolve(source, relativeTo: arguments.package, description: "source")
        guard url.pathExtension == "swift", FileManager.default.fileExists(atPath: url.path) else {
            throw ConsumerError("Missing or non-Swift source: \(source).")
        }
        let name = url.deletingPathExtension().lastPathComponent
        guard !name.isEmpty, names.insert(name).inserted else { throw ConsumerError("Swift base filenames must be unique.") }
    }
    if let mapping = configuration.mapping {
        _ = try resolve(mapping, relativeTo: arguments.package, description: "mapping")
    }
    for resource in configuration.resourceInputs {
        let url = try resolve(resource, relativeTo: arguments.package, description: "resource input")
        guard FileManager.default.fileExists(atPath: url.path) else { throw ConsumerError("Missing resource input: \(resource).") }
    }
    _ = try resolve(configuration.androidOutput, relativeTo: arguments.package, description: "Android output")
    _ = try resolve(configuration.harmonyOutput, relativeTo: arguments.package, description: "HarmonyOS output")
    if let inputs = arguments.explicitInputs {
        for input in inputs + (arguments.mapping.map { [$0] } ?? []) {
            let url = URL(fileURLWithPath: input)
            guard url.path.hasPrefix(arguments.package.path + "/"),
                  url.resolvingSymlinksInPath().path.hasPrefix(arguments.package.resolvingSymlinksInPath().path + "/"),
                  FileManager.default.fileExists(atPath: url.path) else {
                throw ConsumerError("Explicit generator input is missing or outside the consuming package.")
            }
        }
        return (configuration, inputs)
    }
    return (configuration, configuration.sources.map { arguments.package.appendingPathComponent($0).path })
}

func findRefract() throws -> URL {
    if let explicit = ProcessInfo.processInfo.environment["REFRACT_EXECUTABLE"], !explicit.isEmpty {
        let url = URL(fileURLWithPath: explicit)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ConsumerError("REFRACT_EXECUTABLE is not an executable file. Supply the versioned Refract CLI.")
        }
        return url
    }
    let paths = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":") ?? []
    for directory in paths {
        let url = URL(fileURLWithPath: String(directory)).appendingPathComponent("refract")
        if FileManager.default.isExecutableFile(atPath: url.path) { return url }
    }
    throw ConsumerError("Cannot find refract. Set REFRACT_EXECUTABLE to an existing executable or put refract on PATH.")
}

func generate(inputs: [String], mapping: String?, android: URL, harmony: URL) throws {
    var arguments = ["generate"]
    for input in inputs { arguments += ["--input", input] }
    if let mapping { arguments += ["--mapping", mapping] }
    arguments += ["--android-out", android.path, "--harmony-out", harmony.path]
    let process = Process()
    process.executableURL = try findRefract()
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw ConsumerError("Refract generation failed; no committed output was changed.") }
}

func compare(configuration: Configuration, package: URL, android: URL, harmony: URL, publish: Bool) throws -> [URL: Data] {
    var changes: [URL: Data] = [:]
    for source in configuration.sources {
        let basename = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
        for (generatedDirectory, output, ext) in [
            (android, configuration.androidOutput, "kt"),
            (harmony, configuration.harmonyOutput, "ets"),
        ] {
            let generated = generatedDirectory.appendingPathComponent("\(basename).\(ext)")
            let destination = try resolve(output + "/" + basename + "." + ext, relativeTo: package,
                                          description: "committed output")
            let expected = try Data(contentsOf: generated)
            guard FileManager.default.fileExists(atPath: destination.path) else {
                if publish { changes[destination] = expected; continue }
                throw ConsumerError("Missing committed output \(destination.lastPathComponent). Run swift package refract-generate and review it.")
            }
            if try Data(contentsOf: destination) != expected {
                if publish { changes[destination] = expected }
                else { throw ConsumerError("Stale committed output \(destination.lastPathComponent). Run swift package refract-generate and review it.") }
            }
        }
    }
    return changes
}

let arguments: Arguments
do { arguments = try parseArguments() } catch { fail("\(error)") }
let loaded: (configuration: Configuration, inputs: [String])
do { loaded = try loadConfiguration(arguments: arguments) } catch { fail("\(error)") }
let work = arguments.work ?? arguments.package.appendingPathComponent(".build/refract-command")
let android = work.appendingPathComponent("Android", isDirectory: true)
let harmony = work.appendingPathComponent("HarmonyOS", isDirectory: true)
do {
    try generate(inputs: loaded.inputs, mapping: arguments.mapping ?? loaded.configuration.mapping.map {
        arguments.package.appendingPathComponent($0).path
    }, android: android, harmony: harmony)
    let changes = try compare(configuration: loaded.configuration, package: arguments.package,
                              android: android, harmony: harmony, publish: arguments.mode == "publish")
    if arguments.mode == "publish" {
        for (destination, data) in changes {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            print("Updated \(destination.lastPathComponent)")
        }
    }
    if arguments.mode == "generate-and-check" {
        guard let stamp = arguments.work?.appendingPathComponent("RefractBuildAnchor.swift") else { throw ConsumerError("Missing plugin work directory.") }
        try Data("// Generated build-order anchor; no Refract runtime.\n".utf8).write(to: stamp, options: .atomic)
    } else if arguments.mode == "check" {
        print("Refract committed Kotlin and ArkTS outputs match their declared inputs.")
    }
} catch { fail("\(error)") }
