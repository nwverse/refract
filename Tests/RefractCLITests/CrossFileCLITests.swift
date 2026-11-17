import Foundation
import Testing

@Test func cliResolvesExplicitCrossFileInputsAndRejectsAmbiguousOutput() throws {
    #if os(Linux) || os(macOS)
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let fixture = root.appendingPathComponent("Fixtures/cross-file-child-view")
    let executable = crossFileCLIExecutable()
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        Issue.record("Build the refract executable before running CLI integration tests.")
        return
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let android = temporary.appendingPathComponent("android")
    let harmony = temporary.appendingPathComponent("harmony")
    var arguments = ["generate"]
    for name in ["Parent", "ChildRow", "RowItem", "Model"] {
        arguments += ["--input", fixture.appendingPathComponent(name + ".swift").path]
    }
    arguments += ["--mapping", fixture.appendingPathComponent("refract.json").path,
                  "--android-out", android.path, "--harmony-out", harmony.path]
    let generated = try runCrossFileCLI(arguments, executable: executable)
    #expect(generated.status == 0, Comment(rawValue: generated.stderr))
    for name in ["Parent", "ChildRow", "RowItem", "Model"] {
        let expectedKotlin = try String(contentsOf: fixture.appendingPathComponent("Expected.\(name).kt"), encoding: .utf8)
        let expectedArk = try String(contentsOf: fixture.appendingPathComponent("Expected.\(name).ets"), encoding: .utf8)
        #expect(try String(contentsOf: android.appendingPathComponent(name + ".kt"), encoding: .utf8) == expectedKotlin)
        #expect(try String(contentsOf: harmony.appendingPathComponent(name + ".ets"), encoding: .utf8) == expectedArk)
    }
    let parent = try String(contentsOf: harmony.appendingPathComponent("Parent.ets"), encoding: .utf8)
    #expect(parent.contains("import { ChildRow } from './ChildRow';"))
    #expect(!parent.contains("export class RowItem"))

    let rejectedAndroid = temporary.appendingPathComponent("rejected-android")
    let rejectedHarmony = temporary.appendingPathComponent("rejected-harmony")
    let duplicate = temporary.appendingPathComponent("Duplicate.swift")
    try Data("struct RowItem: Identifiable { let id: Int }\n".utf8).write(to: duplicate)
    var rejectedArguments = ["generate", "--input", duplicate.path]
    for name in ["Parent", "ChildRow", "RowItem", "Model"] {
        rejectedArguments += ["--input", fixture.appendingPathComponent(name + ".swift").path]
    }
    rejectedArguments += ["--mapping", fixture.appendingPathComponent("refract.json").path,
                          "--android-out", rejectedAndroid.path, "--harmony-out", rejectedHarmony.path]
    let rejected = try runCrossFileCLI(rejectedArguments, executable: executable)
    #expect(rejected.status != 0)
    #expect(rejected.stderr.contains("[RFVIEW007]"))
    #expect(!FileManager.default.fileExists(atPath: rejectedAndroid.path))
    #expect(!FileManager.default.fileExists(atPath: rejectedHarmony.path))
    #endif
}

private func crossFileCLIExecutable() -> URL {
    if let path = ProcessInfo.processInfo.environment["REFRACT_CLI_PATH"] {
        return URL(fileURLWithPath: path)
    }
    return URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent().appendingPathComponent("refract")
}

private func runCrossFileCLI(_ arguments: [String], executable: URL) throws -> (status: Int32, stderr: String) {
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
