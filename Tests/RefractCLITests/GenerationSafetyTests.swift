import Foundation
import Testing

@Test func cliPreservesCommittedOutputsWhenLaterPublicationFails() throws {
    #if os(Linux) || os(macOS)
    let executable = try requireCLIExecutable()
    let temporary = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporary) }
    let input = temporary.appendingPathComponent("Input.swift")
    try Data("struct Input: View { var body: some View { Text(verbatim: \"New\") } }".utf8).write(to: input)
    let android = temporary.appendingPathComponent("android")
    let harmony = temporary.appendingPathComponent("harmony")
    try FileManager.default.createDirectory(at: android, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: harmony, withIntermediateDirectories: true)
    let committed = ["Input.kt": "old Kotlin", "Other.kt": "unrelated Kotlin"]
    for (name, text) in committed { try Data(text.utf8).write(to: android.appendingPathComponent(name)) }
    let harmonyOutput = harmony.path + "/Input.ets"
    try FileManager.default.createDirectory(atPath: harmonyOutput, withIntermediateDirectories: true)
    try "handwritten".write(toFile: harmonyOutput + "/keep.txt", atomically: true, encoding: .utf8)
    #expect(FileManager.default.fileExists(atPath: harmonyOutput + "/keep.txt"))
    let result = try runCLI(["generate", "--input", input.path, "--android-out", android.path,
                             "--harmony-out", harmony.path], executable: executable)
    #expect(result.status != 0)
    #expect(result.stderr.contains("Input.ets"))
    #expect(result.stderr.contains("No committed generated outputs were changed"))
    for (name, text) in committed {
        #expect(try String(contentsOf: android.appendingPathComponent(name), encoding: .utf8) == text)
    }
    #expect(try String(contentsOfFile: harmonyOutput + "/keep.txt", encoding: .utf8) == "handwritten")
    for directory in [android, harmony] {
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .allSatisfy { !$0.hasPrefix(".refract-") })
    }
    #endif
}

@Test func cliSupportsLegacyNativeMappingAndConcurrentWriters() async throws {
    #if os(Linux) || os(macOS)
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let executable = try requireCLIExecutable()
    let temporary = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporary) }
    let fixture = root.appendingPathComponent("Fixtures/interop-native-component")
    let android = temporary.appendingPathComponent("android")
    let harmony = temporary.appendingPathComponent("harmony")
    let arguments = ["generate", "--input", fixture.appendingPathComponent("Input.swift").path,
                     "--mapping", fixture.appendingPathComponent("refract.json").path,
                     "--android-out", android.path, "--harmony-out", harmony.path]
    let first = try runCLI(arguments, executable: executable)
    #expect(first.status == 0, Comment(rawValue: first.stderr))
    #expect(try String(contentsOf: android.appendingPathComponent("Input.kt"), encoding: .utf8)
        .contains("RoutePreview("))
    #expect(try String(contentsOf: harmony.appendingPathComponent("Input.ets"), encoding: .utf8)
        .contains("RoutePreview("))

    let alternate = temporary.appendingPathComponent("Alternate.swift")
    try Data("struct Alternate: View { var body: some View { Text(verbatim: \"Alternate\") } }".utf8).write(to: alternate)
    let competingArguments = arguments.map { $0 == fixture.appendingPathComponent("Input.swift").path ? alternate.path : $0 }
    let second = try await runCLIConcurrently(arguments, executable: executable, alongside: {
        let results = await withTaskGroup(of: Result<(status: Int32, stderr: String), Error>.self, returning: [Result<(status: Int32, stderr: String), Error>].self) { group in
            for arguments in [arguments, competingArguments, arguments, competingArguments] {
                group.addTask { Result { try runCLI(arguments, executable: executable) } }
            }
            var results: [Result<(status: Int32, stderr: String), Error>] = []
            for await result in group { results.append(result) }
            return results
        }
        for result in results {
            let generation = try result.get()
            #expect(generation.status == 0, Comment(rawValue: generation.stderr))
        }
    })
    #expect(second.status == 0, Comment(rawValue: second.stderr))
    #expect(try runCLI(arguments, executable: executable).status == 0)
    for directory in [android, harmony] {
        let suffix = directory == android ? "kt" : "ets"
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            == ["Alternate.\(suffix)", "Input.\(suffix)"])
        let input = try String(contentsOf: directory.appendingPathComponent("Input.\(suffix)"), encoding: .utf8)
        let alternate = try String(contentsOf: directory.appendingPathComponent("Alternate.\(suffix)"), encoding: .utf8)
        #expect(input.contains("RouteScreen"))
        #expect(alternate.contains("Alternate"))
    }
    #endif
}

@Test func cliReportsInputAndMappingFailuresWithNonzeroExit() throws {
    #if os(Linux) || os(macOS)
    let executable = try requireCLIExecutable()
    let temporary = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporary) }
    let missing = temporary.appendingPathComponent("Missing.swift")
    let android = temporary.appendingPathComponent("android")
    let harmony = temporary.appendingPathComponent("harmony")
    let result = try runCLI(["generate", "--input", missing.path, "--android-out", android.path,
                             "--harmony-out", harmony.path], executable: executable)
    #expect(result.status == 1)
    #expect(result.stderr.contains("cannot read Swift input"))
    #expect(result.stderr.contains("Provide a readable UTF-8 source file"))
    #expect(!FileManager.default.fileExists(atPath: android.path))
    #expect(!FileManager.default.fileExists(atPath: harmony.path))

    let input = temporary.appendingPathComponent("Input.swift")
    let mapping = temporary.appendingPathComponent("refract.json")
    try Data("struct Input: View { var body: some View { Text(verbatim: \"Input\") } }".utf8).write(to: input)
    try Data("{\"schemaVersion\":2}".utf8).write(to: mapping)
    let rejected = try runCLI(["generate", "--input", input.path, "--mapping", mapping.path,
                               "--android-out", android.path, "--harmony-out", harmony.path], executable: executable)
    #expect(rejected.status == 1)
    #expect(rejected.stderr.contains("mappingVersion"))
    #expect(rejected.stderr.contains("Use schema version 1"))
    #endif
}

private func requireCLIExecutable() throws -> URL {
    let executable = builtCLIExecutable()
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        Issue.record("Build the refract executable with `swift build` before running CLI tests.")
        throw CLIHelperError.missingExecutable
    }
    return executable
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("refract-cli-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private enum CLIHelperError: Error { case missingExecutable }

private func runCLIConcurrently(_ arguments: [String], executable: URL,
                                alongside: () async throws -> Void) async throws -> (status: Int32, stderr: String) {
    let launched = try launchCLI(arguments, executable: executable)
    let result = Task { await finishCLI(launched) }
    try await alongside()
    return await result.value
}

private func launchCLI(_ arguments: [String], executable: URL) throws -> (process: Process, stderr: Pipe) {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let stderr = Pipe()
    process.standardError = stderr
    process.standardOutput = Pipe()
    // Process lifetime is coordinated by finishCLI, with a bounded watchdog for a stuck child.
    try process.run()
    return (process, stderr)
}

private func finishCLI(_ launched: (process: Process, stderr: Pipe)) async -> (status: Int32, stderr: String) {
    // Read stderr concurrently with the synchronous exit wait. On Linux, resuming a continuation
    // from terminationHandler before draining the pipe can leave both the child and test runner waiting.
    await withCheckedContinuation { continuation in
        let output = CLIOutput()
        let stderrReader = Thread {
            output.stderr = launched.stderr.fileHandleForReading.readDataToEndOfFile()
        }
        stderrReader.start()
        Thread {
            launched.process.waitUntilExit()
            while output.stderr == nil { Thread.sleep(forTimeInterval: 0.001) }
            continuation.resume(returning: (
                launched.process.terminationStatus,
                String(decoding: output.stderr ?? Data(), as: UTF8.self)
            ))
        }.start()
    }
}

private final class CLIOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    var stderr: Data? {
        get { lock.withLock { data } }
        set { lock.withLock { data = newValue } }
    }
}

private func runCLI(_ arguments: [String], executable: URL) throws -> (status: Int32, stderr: String) {
    let launched = try launchCLI(arguments, executable: executable)
    launched.process.waitUntilExit()
    return (launched.process.terminationStatus,
            String(decoding: launched.stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
}

private func builtCLIExecutable() -> URL {
    if let path = ProcessInfo.processInfo.environment["REFRACT_CLI_PATH"] {
        return URL(fileURLWithPath: path)
    }
    return URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent().appendingPathComponent("refract")
}
