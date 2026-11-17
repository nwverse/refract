import Foundation

extension FixtureCase {
    /// Directory containing a fixture's optional refract.json and native catalogs.
    public var resourceBaseURL: URL? {
        guard mapping != nil else { return nil }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }
}

/// An explicit conformance case. Pending cases are structural contracts, not passing generation tests.
public struct FixtureCorpus: Codable, Sendable {
    public enum ImplementationStatus: String, Codable, Sendable { case ready, pending }
    public struct Entry: Codable, Sendable {
        public let path: String
        public let implementationStatus: ImplementationStatus
        public init(path: String, implementationStatus: ImplementationStatus) {
            self.path = path
            self.implementationStatus = implementationStatus
        }
    }
    public let schemaVersion: Int
    public let cases: [Entry]
    public init(schemaVersion: Int = 1, cases: [Entry]) {
        self.schemaVersion = schemaVersion
        self.cases = cases
    }
}

public struct FixtureCase: Sendable {
    public enum Status: Sendable { case ready, pending }
    public struct Output: Sendable, Equatable {
        public let source: String
        public let kotlin: String
        public let arkTS: String
        public init(source: String, kotlin: String, arkTS: String) {
            self.source = source
            self.kotlin = kotlin
            self.arkTS = arkTS
        }
    }
    public let name: String
    public let status: Status
    public let input: String
    /// Sibling inputs use their Swift basename as the stable key, including `Input.swift`.
    public let additionalInputs: [String: String]
    public let mapping: String?
    public let expectedKotlin: String?
    public let expectedArkTS: String?
    public let expectedDiagnostics: String?
    public let additionalOutputs: [Output]

    public init(name: String, status: Status, input: String, additionalInputs: [String: String] = [:],
                mapping: String?, expectedKotlin: String?, expectedArkTS: String?, expectedDiagnostics: String?,
                additionalOutputs: [Output] = []) {
        self.name = name
        self.status = status
        self.input = input
        self.additionalInputs = additionalInputs
        self.mapping = mapping
        self.expectedKotlin = expectedKotlin
        self.expectedArkTS = expectedArkTS
        self.expectedDiagnostics = expectedDiagnostics
        self.additionalOutputs = additionalOutputs
    }
}

public struct CorpusError: Error, CustomStringConvertible {
    public let code: String
    public let message: String
    public init(code: String, message: String) { self.code = code; self.message = message }
    public var description: String { "\(code): \(message)" }
}

public enum CorpusLoader {
    public static func load(repository root: URL) throws -> [FixtureCase] {
        let fixtures = root.appendingPathComponent("Fixtures", isDirectory: true)
        let manifest = fixtures.appendingPathComponent("Corpus.json")
        let data: Data
        do { data = try Data(contentsOf: manifest) }
        catch { throw CorpusError(code: "corpus.missing", message: "Fixtures/Corpus.json is required.") }
        let corpus: FixtureCorpus
        do { corpus = try JSONDecoder().decode(FixtureCorpus.self, from: data) }
        catch { throw CorpusError(code: "corpus.invalid", message: "Corpus.json must match the versioned schema: \(error).") }
        guard corpus.schemaVersion == 1 else {
            throw CorpusError(code: "corpus.version", message: "Only fixture corpus schema version 1 is supported.")
        }
        guard !corpus.cases.isEmpty else {
            throw CorpusError(code: "corpus.empty", message: "The fixture corpus must contain at least one case.")
        }
        var seen = Set<String>()
        for entry in corpus.cases {
            guard validPath(entry.path) else {
                throw CorpusError(code: "corpus.path", message: "Fixture paths must be relative, clean directories: \(entry.path)")
            }
            guard seen.insert(entry.path).inserted else {
                throw CorpusError(code: "corpus.duplicate", message: "Duplicate fixture entry: \(entry.path)")
            }
        }
        var discovered = Set<String>()
        try discoverDirectories(in: fixtures, relative: "", into: &discovered)
        guard discovered == seen else {
            let missing = seen.subtracting(discovered).sorted().joined(separator: ", ")
            let unknown = discovered.subtracting(seen).sorted().joined(separator: ", ")
            throw CorpusError(code: "corpus.entries", message: "Manifest and fixture directories differ. Missing: \(missing). Unlisted: \(unknown).")
        }
        return try corpus.cases.map { try loadCase(entry: $0, fixtures: fixtures) }
    }

    private static func validPath(_ path: String) -> Bool {
        !path.isEmpty && path != "." && !path.hasPrefix("/") && !path.hasSuffix("/")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                $0.isEmpty || $0 == "." || $0 == ".." || $0.contains("\\")
            })
    }

    private static func discoverDirectories(in root: URL, relative: String, into result: inout Set<String>) throws {
        let directory = relative.isEmpty ? root : root.appendingPathComponent(relative, isDirectory: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            where !name.hasPrefix(".") && !name.hasSuffix(".md") && name != "Corpus.json" {
            let path = relative.isEmpty ? name : relative + "/" + name
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path,
                                                 isDirectory: &isDirectory), isDirectory.boolValue else {
                throw CorpusError(code: "corpus.files", message: "Only case directories and documentation belong in Fixtures: \(path)")
            }
            let pathComponents = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent(name).path)
            if pathComponents.contains("Input.swift") {
                result.insert(path)
            } else {
                try discoverDirectories(in: root, relative: path, into: &result)
            }
        }
    }

    private static func loadCase(entry: FixtureCorpus.Entry, fixtures: URL) throws -> FixtureCase {
        let directory = fixtures.appendingPathComponent(entry.path, isDirectory: true)
        let input = try read(directory, "Input.swift", required: true)
        let mapping = try read(directory, "refract.json", required: false)
        let kotlin = try read(directory, "Expected.kt", required: false)
        let ark = try read(directory, "Expected.ets", required: false)
        let diagnostics = try read(directory, "Expected.diagnostics", required: false)
        let hasSiblingInputs = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .contains { $0.hasSuffix(".swift") && $0 != "Input.swift" }
        let primaryShape = (kotlin != nil && ark != nil && diagnostics == nil) ||
            (kotlin == nil && ark == nil && diagnostics != nil) ||
            (hasSiblingInputs && kotlin == nil && ark == nil && diagnostics == nil)
        guard primaryShape else {
            throw CorpusError(code: "fixture.shape", message: "Case \(entry.path) needs both Expected.kt/Expected.ets, or only Expected.diagnostics; a multi-file case needs per-file Expected.<name> outputs.")
        }
        var additionalInputs: [String: String] = [:]
        var additionalOutputs: [FixtureCase.Output] = []
        for file in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        where file != "Expected.kt" && file != "Expected.ets" {
            if file.hasSuffix(".swift"), file != "Input.swift" {
                guard let contents = try read(directory, file, required: false) else { continue }
                additionalInputs[file] = contents
                continue
            }
            guard file.hasPrefix("Expected."), file.hasSuffix(".kt") || file.hasSuffix(".ets") else { continue }
            let suffix = file.hasSuffix(".kt") ? ".kt" : ".ets"
            let source = String(file.dropFirst("Expected.".count).dropLast(suffix.count))
            guard source != "Input", !source.isEmpty,
                  source.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                throw CorpusError(code: "fixture.shape", message: "Case \(entry.path) has invalid per-file output \(file).")
            }
            guard additionalInputs[source + ".swift"] != nil else {
                throw CorpusError(code: "fixture.shape", message: "Case \(entry.path) output \(file) has no \(source).swift input.")
            }
            guard let kotlin = try read(directory, "Expected.\(source).kt", required: false),
                  let ark = try read(directory, "Expected.\(source).ets", required: false) else {
                throw CorpusError(code: "fixture.shape", message: "Case \(entry.path) needs both per-file outputs for \(source).swift.")
            }
            additionalOutputs.append(FixtureCase.Output(source: source + ".swift", kotlin: kotlin, arkTS: ark))
        }
        if !additionalInputs.isEmpty {
            guard kotlin == nil, ark == nil, additionalOutputs.count == additionalInputs.count,
                  Set(additionalOutputs.map(\.source)) == Set(additionalInputs.keys) else {
                throw CorpusError(code: "fixture.shape", message: "Case \(entry.path) must have one Kotlin/ArkTS output for each named Swift input, with Input.swift reserved for diagnostics.")
            }
        }
        return FixtureCase(name: entry.path,
                           status: entry.implementationStatus == .ready ? .ready : .pending,
                           input: input!, additionalInputs: additionalInputs, mapping: mapping,
                           expectedKotlin: kotlin, expectedArkTS: ark, expectedDiagnostics: diagnostics,
                           additionalOutputs: additionalOutputs)
    }

    private static func read(_ directory: URL, _ name: String, required: Bool) throws -> String? {
        let url = directory.appendingPathComponent(name)
        if !required, !FileManager.default.fileExists(atPath: url.path) { return nil }
        do { return try String(contentsOf: url, encoding: .utf8) }
        catch { throw CorpusError(code: "fixture.read", message: "Cannot read \(url.lastPathComponent): \(error).") }
    }
}
