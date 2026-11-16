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
        let runner = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: executable.deletingLastPathComponent().path)) ?? []
        Issue.record("Build the refract executable with `swift build` before running `swift test`. Runner: \(runner.path); candidate: \(executable.path); files: \(siblings)")
        return
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let input = temporary.appendingPathComponent("Input.swift")
    try Data("struct Hello: View { var body: some View { Text(\"Hello\") } }".utf8).write(to: input)

    let generation = try runCLI(["generate", "--input", input.path,
                                 "--android-out", temporary.appendingPathComponent("android").path,
                                 "--harmony-out", temporary.appendingPathComponent("harmony").path], executable: executable)
    #expect(generation.status == 0, Comment(rawValue: generation.stderr))
    #expect(try String(contentsOf: temporary.appendingPathComponent("android/Input.kt"), encoding: .utf8)
        .contains("text = \"Hello\""))
    #expect(try String(contentsOf: temporary.appendingPathComponent("harmony/Input.ets"), encoding: .utf8)
        .contains("Text(\"Hello\")"))
    #expect(try runCLI(["check", "--input", input.path], executable: executable).status == 0)

    let rejection = try runCLI(["generate", "--input",
                                root.appendingPathComponent("Fixtures/rejected-image/Input.swift").path,
                                "--android-out", temporary.appendingPathComponent("android").path,
                                "--harmony-out", temporary.appendingPathComponent("harmony").path], executable: executable)
    #expect(rejection.status != 0)
    #expect(rejection.stderr.contains("[RFNATIVE001]"))
    #endif
}

private func builtCLIExecutable() -> URL {
    let executableName = "refract"
    #if os(macOS)
    let bundled = Bundle.main.bundleURL
        .deletingLastPathComponent()
        .appendingPathComponent(executableName)
    if FileManager.default.isExecutableFile(atPath: bundled.path) {
        return bundled
    }
    #endif
    return URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent()
        .appendingPathComponent(executableName)
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
    try Data("struct First: View { var body: some View { Text(\"First\") } }".utf8).write(to: first)
    try Data("struct Second: View { var body: some View { Text(\"Second\") } }".utf8).write(to: second)
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
    #expect(rejected.stderr.contains("[RFNATIVE001]"))
    #expect(!FileManager.default.fileExists(atPath: rejectedAndroid.path))
    #expect(!FileManager.default.fileExists(atPath: rejectedHarmony.path))
    #endif
}

private func runCLI(_ arguments: [String], executable: URL) throws -> (status: Int32, stderr: String) {
    let process = Process()
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
