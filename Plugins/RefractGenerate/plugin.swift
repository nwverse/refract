import Foundation
import PackagePlugin

@main
struct RefractGenerate: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = ArgumentExtractor(arguments)
        _ = extractor.extractFlag(named: "allow-writing-to-package-directory")
        let targets = extractor.extractOption(named: "target")
        guard targets.count == 1, extractor.remainingArguments.isEmpty else {
            throw PluginError(message: "Usage: swift package refract-generate --target <name>.")
        }
        let tool = try context.tool(named: "RefractConsumerTool").url
        let generator: URL
        if let explicit = ProcessInfo.processInfo.environment["REFRACT_EXECUTABLE"], !explicit.isEmpty {
            generator = URL(fileURLWithPath: explicit)
            let values = try? generator.resourceValues(forKeys: [.isRegularFileKey, .isExecutableKey])
            guard values?.isRegularFile == true, values?.isExecutable == true else {
                throw PluginError(message: "REFRACT_EXECUTABLE is not an executable file: \(explicit)")
            }
        } else {
            do { generator = try context.tool(named: "RefractCLI").url }
            catch {
                throw PluginError(message: "Cannot find refract. Set REFRACT_EXECUTABLE to an existing executable or put refract on PATH.")
            }
        }
        let process = Process()
        process.executableURL = tool
        process.arguments = ["publish", "--package", context.package.directoryURL.path, "--target", targets[0]]
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
