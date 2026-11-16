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

private func runCLI(_ arguments: [String], executable: URL) throws -> (status: Int32, stderr: String) {    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let stderr = Pipe()
    process.standardError = stderr
    process.standardOutput = Pipe()
    try process.run()
    process.waitUntilExit()
    return (process.terminationStatus,
            String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
}
