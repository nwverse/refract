import Foundation
import PackagePlugin

@main
struct RefractGenerate: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = ArgumentExtractor(arguments)
        _ = extractor.extractFlag(named: "allow-writing-to-package-directory")
        let check = extractor.extractFlag(named: "check")
        let targets = extractor.extractOption(named: "target")
        guard check <= 1, targets.count == 1, extractor.remainingArguments.isEmpty else {
            throw PluginError(message: "Usage: swift package refract-generate --target <name> [--check].")
        }
        let tool = try context.tool(named: "RefractConsumerTool").url
        let generator: URL
        if let explicit = ProcessInfo.processInfo.environment["REFRACT_EXECUTABLE"], !explicit.isEmpty {
            generator = URL(fileURLWithPath: explicit)
            guard FileManager.default.isExecutableFile(atPath: generator.path) else {
                throw PluginError(message: "REFRACT_EXECUTABLE is not an executable file: \(explicit)")
            }
        } else {
            do { generator = try context.tool(named: "RefractCLI").url }
            catch {
                throw PluginError(message: "Cannot find refract. Set REFRACT_EXECUTABLE to an existing executable or put refract on PATH.")
            }
        }
        let arguments = [check == 1 ? "check" : "publish", "--package", context.package.directoryURL.path,
                         "--target", targets[0]]
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.environment = ["REFRACT_EXECUTABLE": generator.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw PluginError(message: "Refract did not complete.") }
    }
}

struct PluginError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
