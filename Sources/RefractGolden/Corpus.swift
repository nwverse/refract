import Foundation

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
    public let name: String
    public let status: Status
    public let input: String
    public let mapping: String?
    public let expectedKotlin: String?
    public let expectedArkTS: String?
    public let expectedDiagnostics: String?
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
        guard (kotlin != nil && ark != nil && diagnostics == nil) || (kotlin == nil && ark == nil && diagnostics != nil) else {
            throw CorpusError(code: "fixture.shape", message: "Case \(entry.path) needs both Expected.kt/Expected.ets, or only Expected.diagnostics.")
        }
        return FixtureCase(name: entry.path,
                           status: entry.implementationStatus == .ready ? .ready : .pending,
                           input: input!, mapping: mapping,
                           expectedKotlin: kotlin, expectedArkTS: ark, expectedDiagnostics: diagnostics)
    }

    private static func read(_ directory: URL, _ name: String, required: Bool) throws -> String? {
        let url = directory.appendingPathComponent(name)
        if !required, !FileManager.default.fileExists(atPath: url.path) { return nil }
        do { return try String(contentsOf: url, encoding: .utf8) }
        catch { throw CorpusError(code: "fixture.read", message: "Cannot read \(url.lastPathComponent): \(error).") }
    }
}
