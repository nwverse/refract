import Foundation
import Testing

#if os(Linux) || os(macOS)
@Test func textInputHostCLIRejectsMissingBodyWithoutPublishingNativeOutput() throws {
    let fixture = textInputHostFixture()
    let canonical = try String(contentsOf: fixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    guard let bodyStart = canonical.range(of: "    var body: some View {"),
          let bodyEnd = canonical.range(of: "\n    }", range: bodyStart.lowerBound..<canonical.endIndex) else {
        Issue.record("Expected the complete native host body")
        return
    }
    var missingBody = canonical
    missingBody.removeSubrange(bodyStart.lowerBound..<bodyEnd.upperBound)
    #expect(!missingBody.contains("TextField"))
    let result = try runTextInputHostCLI(source: missingBody, fixture: fixture)
    #expect(result.status == 1, Comment(rawValue: result.stderr))
    #expect(result.stderr.components(separatedBy: "[RFINPUT001]").count == 2)
    #expect(result.stderr.contains("complete five-input signature and SwiftUI body"))
    #expect(result.stderr.components(separatedBy: "[RFINPUT002]").count == 2)
    #expect(result.generatedFiles.isEmpty)
}

@Test func textInputHostCLIAcceptsEquivalentBodySpellingWithCanonicalOutput() throws {
    let fixture = textInputHostFixture()
    let canonical = try String(contentsOf: fixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    let variants = [
        replacing(in: canonical, [".onChange(of: focusRequest) { _, _ in",
                  ".onChange(of: focusRequest) { (oldValue: Int, newValue: Int) -> Void in",
                  ".onSubmit {", ".onSubmit { () -> Void in"]),
        replacing(in: canonical, ["        TextField(\"Message\", text: $draft)",
                  "        return (TextField(\"Message\", text: $draft))"]),
        replacing(in: canonical, ["        TextField(\"Message\", text: $draft)",
                  "        (TextField(\"Message\", text: $draft))"]),
        replacing(in: canonical, [
                  "$isHostFocused", "$self.isHostFocused",
                  "of: focusRequest", "of: self.focusRequest",
                  "isHostFocused = true", "self.isHostFocused = true",
                  "onDraftCommit(draft)", "self.onDraftCommit(self.draft)",
                  "                onCommit()", "                self.onCommit()"]),
    ]
    for source in variants + [canonical] {
        let result = try runTextInputHostCLI(source: source, fixture: fixture)
        #expect(result.status == 0, Comment(rawValue: result.stderr))
        #expect(result.generatedFiles.count == 2)
        for platform in ["kt", "ets"] {
            let expected = try Data(contentsOf: fixture.appendingPathComponent("Expected.\(platform)"))
            #expect(result.generatedFiles[platform] == expected)
        }
    }
}

@Test func textInputHostCLIInvalidPresentBodyKeepsDedicatedDiagnostic() throws {
    let fixture = textInputHostFixture()
    let canonical = try String(contentsOf: fixture.appendingPathComponent("Input.swift"), encoding: .utf8)
    let textOnly = replacing(in: canonical, ["TextField(\"Message\", text: $draft)", "Text(\"Message\")"])
    let result = try runTextInputHostCLI(source: textOnly, fixture: fixture)
    #expect(result.status == 1, Comment(rawValue: result.stderr))
    #expect(result.stderr.components(separatedBy: "[RFINPUT001]").count == 2)
    #expect(result.stderr.contains("must use TextField"))
    #expect(!result.stderr.contains("complete five-input signature"))
    #expect(result.stderr.components(separatedBy: "[RFINPUT002]").count == 2)
    #expect(result.generatedFiles.isEmpty)
}

private func replacing(in source: String, _ pairs: [String],
                       fileID: StaticString = #fileID, line: UInt = #line) -> String {
    precondition(pairs.count.isMultiple(of: 2), "Replacements need old/new pairs", file: fileID, line: line)
    var result = source
    for index in stride(from: 0, to: pairs.count, by: 2) {
        precondition(result.contains(pairs[index]), "Replacement must match its source", file: fileID, line: line)
        result = result.replacingOccurrences(of: pairs[index], with: pairs[index + 1])
    }
    return result
}

private func textInputHostFixture() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/interop-text-input-host")
}

private func runTextInputHostCLI(source: String, fixture: URL) throws
    -> (status: Int32, stderr: String, generatedFiles: [String: Data]) {
    let executable: URL
    if let path = ProcessInfo.processInfo.environment["REFRACT_CLI_PATH"] {
        executable = URL(fileURLWithPath: path)
    } else {
        executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            .appendingPathComponent("refract")
    }
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        Issue.record("Build the refract executable before running CLI tests.")
        return (1, "The CLI is not built", [:])
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let input = temporary.appendingPathComponent("Input.swift")
    try Data(source.utf8).write(to: input)
    let android = temporary.appendingPathComponent("android")
    let harmony = temporary.appendingPathComponent("harmony")
    let process = Process()
    process.executableURL = executable
    process.arguments = ["generate", "--input", input.path,
                         "--mapping", fixture.appendingPathComponent("refract.json").path,
                         "--android-out", android.path, "--harmony-out", harmony.path]
    let stderr = Pipe()
    process.standardOutput = Pipe()
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    var files: [String: Data] = [:]
    for (directory, platform) in [(android, "kt"), (harmony, "ets")] {
        let output = directory.appendingPathComponent("Input.\(platform)")
        if let data = FileManager.default.contents(atPath: output.path) { files[platform] = data }
    }
    return (process.terminationStatus,
            String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), files)
}
#endif
