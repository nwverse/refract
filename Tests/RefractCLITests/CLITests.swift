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
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        .appendingPathComponent("refract")
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        Issue.record("Build the refract executable with `swift build` before running `swift test`.")
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
    #expect(rejection.stderr.contains("[RFNATIVE001]"))
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
