import Testing
import Foundation

@Test func cliCheckFailsClosedWithoutWritingOutputs() throws {
    #if os(Linux) || os(macOS)
    let executable = checkCLIExecutable()
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        Issue.record("Build the refract executable before running CLI tests.")
        return
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let first = temporary.appendingPathComponent("First.swift")
    let second = temporary.appendingPathComponent("Second.swift")
    let android = temporary.appendingPathComponent("android")
    let harmony = temporary.appendingPathComponent("harmony")
    let mapping = temporary.appendingPathComponent("refract.json")
    try Data("struct First: View { var body: some View { Text(verbatim: \"First\") } }".utf8).write(to: first)
    try Data("struct Second: View { var body: some View { Text(verbatim: \"Second\") } }".utf8).write(to: second)
    let mappingJSON: [String: Any] = [
        "schemaVersion": 1,
        "android": [
            "output": ["directory": "ignored", "packageName": "refract.generated"],
            "imports": [], "components": [:], "nativeComponents": [:], "modifiers": [:],
            "tokens": ["spacing": [:], "radius": [:], "font": [:], "color": [:]],
            "resources": ["className": "example.resources.R", "strings": [:]],
        ],
        "harmonyOS": [
            "output": ["directory": "ignored"],
            "imports": [], "components": [:], "nativeComponents": [:], "modifiers": [:],
            "tokens": ["spacing": [:], "radius": [:], "font": [:], "color": [:]],
            "resources": ["namespace": "app", "stringTable": "string", "strings": [:]],
        ],
    ]
    try JSONSerialization.data(withJSONObject: mappingJSON).write(to: mapping)
    let arguments = ["--input", first.path, "--input", second.path, "--mapping", mapping.path,
                     "--android-out", android.path, "--harmony-out", harmony.path]
    let malformed = temporary.appendingPathComponent("Malformed.swift")
    try Data("struct Malformed: View { var body: some View { Text(verbatim: \"broken\") }".utf8)
        .write(to: malformed)
    let invalid = try runCheckCLI(["check", "--input", malformed.path,
                                   "--android-out", android.path, "--harmony-out", harmony.path], executable: executable)
    #expect(invalid.status != 0)
    #expect(invalid.stderr.contains("[RFSYN001]"))
    #expect(!invalid.stderr.contains("missing committed output"))
    #expect(!FileManager.default.fileExists(atPath: android.path))
    #expect(!FileManager.default.fileExists(atPath: harmony.path))

    let missing = try runCheckCLI(["check"] + arguments, executable: executable)
    #expect(missing.status != 0)
    #expect(missing.stderr.contains("missing committed output"))
    #expect(missing.stderr.contains(android.appendingPathComponent("First.kt").path))
    #expect(missing.stderr.contains(harmony.appendingPathComponent("Second.ets").path))
    #expect(missing.stderr.contains("4 committed output(s)"))
    #expect(!FileManager.default.fileExists(atPath: android.path))
    #expect(!FileManager.default.fileExists(atPath: harmony.path))

    let generated = try runCheckCLI(["generate"] + arguments, executable: executable)
    #expect(generated.status == 0, Comment(rawValue: generated.stderr))
    let clean = try runCheckCLI(["check"] + arguments, executable: executable)
    #expect(clean.status == 0, Comment(rawValue: clean.stderr))
    #expect(clean.stderr.isEmpty)
    let repeated = try runCheckCLI(["check"] + arguments, executable: executable)
    #expect(repeated.status == 0, Comment(rawValue: repeated.stderr))
    let extra = android.appendingPathComponent("Removed.kt")
    try Data("// obsolete\n".utf8).write(to: extra)
    let unexpected = try runCheckCLI(["check"] + arguments, executable: executable)
    #expect(unexpected.status != 0)
    #expect(unexpected.stderr.contains("unexpected generated output \(extra.path)"))
    #expect(try Data(contentsOf: extra) == Data("// obsolete\n".utf8))
    try FileManager.default.removeItem(at: extra)
    #expect(try runCheckCLI(["check"] + arguments, executable: executable).status == 0)

    let staleKotlin = android.appendingPathComponent("First.kt")
    let staleArkTS = harmony.appendingPathComponent("Second.ets")
    let originalKotlin = try Data(contentsOf: staleKotlin)
    let originalArkTS = try Data(contentsOf: staleArkTS)
    try Data("// hand edit\n".utf8).write(to: staleKotlin)
    try Data("// hand edit\n".utf8).write(to: staleArkTS)
    let stale = try runCheckCLI(["check"] + arguments, executable: executable)
    #expect(stale.status != 0)
    #expect(stale.stderr.contains("stale committed output \(staleKotlin.path)"))
    #expect(stale.stderr.contains("stale committed output \(staleArkTS.path)"))
    #expect(stale.stderr.contains("refract generate"))
    #expect(stale.stderr.contains("2 committed output(s)"))
    #expect(try Data(contentsOf: staleKotlin) == Data("// hand edit\n".utf8))
    #expect(try Data(contentsOf: staleArkTS) == Data("// hand edit\n".utf8))
    try originalKotlin.write(to: staleKotlin)
    try originalArkTS.write(to: staleArkTS)

    try Data("struct Second: View { var body: some View { Text(verbatim: \"Changed\") } }".utf8).write(to: second)
    let changedInput = try runCheckCLI(["check"] + arguments, executable: executable)
    #expect(changedInput.status != 0)
    #expect(changedInput.stderr.contains("Second.kt"))
    #expect(changedInput.stderr.contains("Second.ets"))
    let regenerated = try runCheckCLI(["generate"] + arguments, executable: executable)
    #expect(regenerated.status == 0, Comment(rawValue: regenerated.stderr))
    let originalMapping = try Data(contentsOf: mapping)
    var changedMapping = mappingJSON
    var changedAndroid = changedMapping["android"] as! [String: Any]
    changedAndroid["imports"] = ["example.components.Unused"]
    changedMapping["android"] = changedAndroid
    try JSONSerialization.data(withJSONObject: changedMapping).write(to: mapping)
    let changedConfiguration = try runCheckCLI(["check"] + arguments, executable: executable)
    #expect(changedConfiguration.status != 0)
    #expect(changedConfiguration.stderr.contains("stale committed output"))
    try originalMapping.write(to: mapping)
    #expect(try runCheckCLI(["check"] + arguments, executable: executable).status == 0)

    let localized = temporary.appendingPathComponent("Localized.swift")
    let localizedAndroid = temporary.appendingPathComponent("localized-android")
    let localizedHarmony = temporary.appendingPathComponent("localized-harmony")
    try Data("struct Localized: View { var body: some View { Text(\"example.title\") } }".utf8).write(to: localized)
    var localizedMapping = mappingJSON
    var androidMapping = localizedMapping["android"] as! [String: Any]
    androidMapping["resources"] = ["className": "example.resources.R", "catalog": "strings.xml",
                                   "strings": ["example.title": "example_title"]]
    localizedMapping["android"] = androidMapping
    var harmonyMapping = localizedMapping["harmonyOS"] as! [String: Any]
    harmonyMapping["resources"] = ["namespace": "app", "stringTable": "string", "catalog": "string.json",
                                   "strings": ["example.title": "example_title"]]
    localizedMapping["harmonyOS"] = harmonyMapping
    try JSONSerialization.data(withJSONObject: localizedMapping).write(to: mapping)
    let catalog = temporary.appendingPathComponent("strings.xml")
    try Data("<resources><string name=\"example_title\">Hello</string></resources>".utf8).write(to: catalog)
    try Data("{\"string\":[{\"name\":\"example_title\",\"value\":\"Hello\"}]}".utf8)
        .write(to: temporary.appendingPathComponent("string.json"))
    let localizedArguments = ["--input", localized.path, "--mapping", mapping.path,
                              "--android-out", localizedAndroid.path, "--harmony-out", localizedHarmony.path]
    let localizedGeneration = try runCheckCLI(["generate"] + localizedArguments, executable: executable)
    #expect(localizedGeneration.status == 0, Comment(rawValue: localizedGeneration.stderr))
    #expect(try runCheckCLI(["check"] + localizedArguments, executable: executable).status == 0)
    let originalLocalizedKotlin = try Data(contentsOf: localizedAndroid.appendingPathComponent("Localized.kt"))
    let originalLocalizedArkTS = try Data(contentsOf: localizedHarmony.appendingPathComponent("Localized.ets"))
    try Data("<resources/>".utf8).write(to: catalog)
    let changedCatalog = try runCheckCLI(["check"] + localizedArguments, executable: executable)
    #expect(changedCatalog.status != 0)
    #expect(changedCatalog.stderr.contains("[R.string.missing_android]"))
    #expect(try Data(contentsOf: localizedAndroid.appendingPathComponent("Localized.kt")) == originalLocalizedKotlin)
    #expect(try Data(contentsOf: localizedHarmony.appendingPathComponent("Localized.ets")) == originalLocalizedArkTS)
    #endif
}

private func checkCLIExecutable() -> URL {
    if let path = ProcessInfo.processInfo.environment["REFRACT_CLI_PATH"] {
        return URL(fileURLWithPath: path)
    }
    return URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent()
        .appendingPathComponent("refract")
}

private func runCheckCLI(_ arguments: [String], executable: URL) throws -> (status: Int32, stderr: String) {
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
