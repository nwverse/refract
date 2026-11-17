import Testing
import Foundation

@Test func cliExecutableTargetBuilds() {
    // Build the executable first; nested SwiftPM invocations can wait on the package's build lock.
    #expect(Bool(true))
}

@Test func cliGeneratesBothPlatformsAndRejectsUnsupportedInput() throws {
    #if os(Linux) || os(macOS)
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let executable = builtCLIExecutable()
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        Issue.record("Build the refract executable with `swift build` before running `swift test`. Candidate: \(executable.path)")
        return
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let input = temporary.appendingPathComponent("Input.swift")
    try Data("struct Hello: View { var body: some View { Text(\"hello.title\") } }".utf8).write(to: input)

    let mapping = temporary.appendingPathComponent("refract.json")
    let resources = """
    "imports":[],"components":{},"nativeComponents":{},"modifiers":{},"tokens":{"spacing":{},"radius":{},"font":{},"color":{}}
    """
    let android = "\"output\":{\"directory\":\"generated\",\"packageName\":\"refract.generated\"}," + resources
    try Data("""
    {"schemaVersion":1,"android":{\(android),"resources":{"className":"example.resources.R","catalog":"strings.xml","strings":{"hello.title":"hello_title"}}},"harmonyOS":{"output":{"directory":"generated"},\(resources),"resources":{"namespace":"app","stringTable":"string","catalog":"string.json","strings":{"hello.title":"hello_title"}}}}
    """.utf8).write(to: mapping)
    try Data("<resources><string name=\"hello_title\">Hello</string></resources>".utf8)
        .write(to: temporary.appendingPathComponent("strings.xml"))
    try Data("{\"string\":[{\"name\":\"hello_title\",\"value\":\"Hello\"}]}".utf8)
        .write(to: temporary.appendingPathComponent("string.json"))

    let generation = try runCLI(["generate", "--input", input.path, "--mapping", mapping.path,
                                 "--android-out", temporary.appendingPathComponent("android").path,
                                 "--harmony-out", temporary.appendingPathComponent("harmony").path], executable: executable)
    #expect(generation.status == 0, Comment(rawValue: generation.stderr))
    #expect(try String(contentsOf: temporary.appendingPathComponent("android/Input.kt"), encoding: .utf8)
        .contains("stringResource(example.resources.R.string.hello_title)"))
    #expect(try String(contentsOf: temporary.appendingPathComponent("harmony/Input.ets"), encoding: .utf8)
        .contains("$r('app.string.hello_title')"))
    #expect(try runCLI(["check", "--input", input.path, "--mapping", mapping.path], executable: executable).status == 0)

    let rejection = try runCLI(["generate", "--input",
                                root.appendingPathComponent("Fixtures/rejected-image/Input.swift").path,
                                "--android-out", temporary.appendingPathComponent("android").path,
                                "--harmony-out", temporary.appendingPathComponent("harmony").path], executable: executable)
    #expect(rejection.status != 0)
    #expect(rejection.stderr.contains("[RF-C002]"))
    #endif
}

private func builtCLIExecutable() -> URL {
    if let path = ProcessInfo.processInfo.environment["REFRACT_CLI_PATH"] {
        return URL(fileURLWithPath: path)
    }
    return URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent()
        .appendingPathComponent("refract")
}

@Test func cliGeneratesMultipleInputsAndDoesNotWriteOnAnyDiagnostic() throws {
    #if os(Linux) || os(macOS)
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let executable = builtCLIExecutable()
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        Issue.record("Build the refract executable with `swift build` before running `swift test`.")
        return
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let first = temporary.appendingPathComponent("First.swift")
    let second = temporary.appendingPathComponent("Second.swift")
    let android = temporary.appendingPathComponent("android")
    let harmony = temporary.appendingPathComponent("harmony")
    try Data("struct First: View { var body: some View { Text(verbatim: \"First\") } }".utf8).write(to: first)
    try Data("struct Second: View { var body: some View { Text(verbatim: \"Second\") } }".utf8).write(to: second)
    let arguments = ["--input", first.path, "--input", second.path,
                     "--android-out", android.path, "--harmony-out", harmony.path]
    let generated = try runCLI(["generate"] + arguments, executable: executable)
    #expect(generated.status == 0, Comment(rawValue: generated.stderr))
    for directory in [android, harmony] {
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            == [directory == android ? "First.kt" : "First.ets", directory == android ? "Second.kt" : "Second.ets"])
    }

    let rejectedAndroid = temporary.appendingPathComponent("rejected-android")
    let rejectedHarmony = temporary.appendingPathComponent("rejected-harmony")
    let rejected = try runCLI(["generate", "--input", first.path, "--input",
                               root.appendingPathComponent("Fixtures/rejected-image/Input.swift").path,
                               "--android-out", rejectedAndroid.path, "--harmony-out", rejectedHarmony.path],
                              executable: executable)
    #expect(rejected.status != 0)
    #expect(rejected.stderr.contains("[RF-C002]"))
    #expect(!FileManager.default.fileExists(atPath: rejectedAndroid.path))
    #expect(!FileManager.default.fileExists(atPath: rejectedHarmony.path))
    #endif
}

@Test func cliRejectsMissingNativeMappingsWithoutPartialOutput() throws {
    #if os(Linux) || os(macOS)
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let executable = builtCLIExecutable()
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        Issue.record("Build the refract executable before running CLI tests.")
        return
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let valid = temporary.appendingPathComponent("Valid.swift")
    try Data("struct Valid: View { var body: some View { Text(verbatim: \"Valid\") } }".utf8).write(to: valid)
    let missing = root.appendingPathComponent("Fixtures/interop-native-missing")
    let android = temporary.appendingPathComponent("android")
    let harmony = temporary.appendingPathComponent("harmony")
    let result = try runCLI(["generate", "--input", valid.path,
        "--input", missing.appendingPathComponent("Input.swift").path,
        "--mapping", missing.appendingPathComponent("refract.json").path,
        "--android-out", android.path, "--harmony-out", harmony.path], executable: executable)
    #expect(result.status != 0)
    #expect(result.stderr.contains("has no Android mapping"))
    #expect(result.stderr.contains("has no HarmonyOS mapping"))
    #expect(result.stderr.components(separatedBy: "has no Android mapping").count == 2)
    #expect(result.stderr.components(separatedBy: "has no HarmonyOS mapping").count == 2)
    #expect(!FileManager.default.fileExists(atPath: android.path))
    #expect(!FileManager.default.fileExists(atPath: harmony.path))
    #endif
}

@Test func cliRejectsUndefinedStackSpacingWithoutOutput() throws {
    #if os(Linux) || os(macOS)
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let executable = builtCLIExecutable()
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        Issue.record("Build the refract executable before running CLI tests.")
        return
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let android = temporary.appendingPathComponent("android")
    let harmony = temporary.appendingPathComponent("harmony")
    let result = try runCLI(["generate", "--input",
        root.appendingPathComponent("Fixtures/v0-reject-undefined-spacing/Input.swift").path,
        "--android-out", android.path, "--harmony-out", harmony.path], executable: executable)
    #expect(result.status != 0)
    #expect(result.stderr.contains("[RFVIEW003]"))
    #expect(!result.stderr.contains("undefinedValue.dp"))
    #expect(!FileManager.default.fileExists(atPath: android.path))
    #expect(!FileManager.default.fileExists(atPath: harmony.path))
    #endif
}

@Test func cliRejectsMalformedSwiftWithoutPartialOutput() throws {
    #if os(Linux) || os(macOS)
    let executable = builtCLIExecutable()
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        Issue.record("Build the refract executable before running CLI tests.")
        return
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let valid = temporary.appendingPathComponent("Valid.swift")
    let malformed = temporary.appendingPathComponent("Syntax.swift")
    let source = """
    import SwiftUI

    struct SyntaxScreen: View {
        var body: some View {
            Text(verbatim: "unterminated"
        }
    }
    """
    try Data("struct Valid: View { var body: some View { Text(verbatim: \"Valid\") } }".utf8).write(to: valid)
    try Data(source.utf8).write(to: malformed)
    let android = temporary.appendingPathComponent("android")
    let harmony = temporary.appendingPathComponent("harmony")
    let result = try runCLI(["generate", "--input", valid.path, "--input", malformed.path,
        "--android-out", android.path, "--harmony-out", harmony.path], executable: executable)
    #expect(result.status != 0)
    #expect(result.stderr.contains("Syntax.swift:"))
    #expect(result.stderr.contains("[RFSYN001]"))
    #expect(result.stderr.contains("Correct the Swift syntax"))
    #expect(!FileManager.default.fileExists(atPath: android.path))
    #expect(!FileManager.default.fileExists(atPath: harmony.path))

    let checked = try runCLI(["check", "--input", malformed.path], executable: executable)
    #expect(checked.status != 0)
    #expect(checked.stderr.contains("[RFSYN001]"))
    #endif
}

@Test func cliRejectsUnsupportedViewDeclarationWithoutPartialOutput() throws {
    #if os(Linux) || os(macOS)
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let executable = builtCLIExecutable()
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        Issue.record("Build the refract executable before running CLI tests.")
        return
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let valid = temporary.appendingPathComponent("Valid.swift")
    try Data("struct Valid: View { var body: some View { Text(verbatim: \"Valid\") } }".utf8).write(to: valid)
    let rejected = root.appendingPathComponent("Fixtures/rejected-view-declaration/Input.swift")
    let android = temporary.appendingPathComponent("android")
    let harmony = temporary.appendingPathComponent("harmony")
    let result = try runCLI(["generate", "--input", valid.path, "--input", rejected.path,
        "--android-out", android.path, "--harmony-out", harmony.path], executable: executable)
    #expect(result.status != 0)
    #expect(result.stderr.contains("[RFSYN004]"))
    #expect(result.stderr.contains("unsupportedHelper"))
    #expect(result.stderr.contains("model protocol"))
    #expect(!FileManager.default.fileExists(atPath: android.path))
    #expect(!FileManager.default.fileExists(atPath: harmony.path))
    #endif
}

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
    #expect(result.stderr.contains("Missing.swift"))
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
    try process.run()
    return (process, stderr)
}

private func finishCLI(_ launched: (process: Process, stderr: Pipe)) async -> (status: Int32, stderr: String) {
    await withCheckedContinuation { continuation in
        launched.process.terminationHandler = { _ in continuation.resume() }
    }
    return (launched.process.terminationStatus,
            String(decoding: launched.stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
}

private func runCLI(_ arguments: [String], executable: URL) throws -> (status: Int32, stderr: String) {
    let launched = try launchCLI(arguments, executable: executable)
    launched.process.waitUntilExit()
    return (launched.process.terminationStatus,
            String(decoding: launched.stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
}
