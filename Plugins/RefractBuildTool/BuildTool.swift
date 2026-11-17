import Foundation
import PackagePlugin

@main
struct RefractSwiftPMPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let target = target as? SourceModuleTarget else {
            throw PluginError(message: "RefractSwiftPMPlugin requires a source-module target.")
        }
        let package = context.package.directoryURL
        let configurationURL = package.appendingPathComponent("refract-swiftpm.json")
        let configuration = try ConsumerConfiguration.load(
            url: configurationURL, package: package, target: target.name)
        let targetSources = Set(target.sourceFiles.map { $0.url.standardizedFileURL.path })
        var inputs = [configurationURL]
        var arguments = ["generate-and-check", "--package", package.path,
                         "--target", target.name, "--plugin-work", context.pluginWorkDirectoryURL.path]
        for source in configuration.sources {
            let url = try configuration.resolve(source, description: "Swift input")
            guard targetSources.contains(url.standardizedFileURL.path) else {
                throw PluginError(message: "Declared input \(source) must compile in target \(target.name); do not copy it for iOS.")
            }
            inputs.append(url)
            arguments += ["--input", url.path]
        }
        if let mapping = configuration.mapping {
            let url = try configuration.resolve(mapping, description: "mapping")
            inputs.append(url)
            arguments += ["--mapping", url.path]
        }
        for resource in try configuration.mappingCatalogs() + configuration.resourceInputs.map({
            try configuration.resolve($0, description: "resource input")
        }) {
            inputs.append(resource)
            arguments += ["--dependency", resource.path]
        }
        for output in configuration.committedOutputs {
            // Committed native files are read-only build inputs. Editing or removing
            // one invalidates the check without granting package-directory writes.
            inputs.append(output)
        }
        // A direct-file manifest notices added/removed .kt/.ets files, which cannot
        // be inferred from the declared per-input outputs. The CLI owns their check.
        for directory in configuration.committedOutputDirectories {
            let manifest = context.pluginWorkDirectoryURL.appendingPathComponent(
                directory.lastPathComponent + "-inputs.txt")
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { ["kt", "ets"].contains(URL(fileURLWithPath: $0).pathExtension) }.sorted()
            let listing = try files.map { name in
                let file = directory.appendingPathComponent(name)
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return "\(name)\t\(values.fileSize ?? -1)\t\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            }.joined(separator: "\n")
            let data = Data((listing + "\n").utf8)
            if (try? Data(contentsOf: manifest)) != data {
                try data.write(to: manifest, options: .atomic)
            }
            inputs.append(manifest)
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
            do {
                generator = try context.tool(named: "RefractCLI").url
            } catch {
                throw PluginError(message: "Cannot find refract. Set REFRACT_EXECUTABLE to an existing executable or put refract on PATH.")
            }
        }
        inputs.append(contentsOf: [tool, generator])
        let anchor = context.pluginWorkDirectoryURL.appendingPathComponent("RefractBuildAnchor.swift")
        return [.buildCommand(
            displayName: "Generate and verify native sources with Refract",
            executable: tool,
            arguments: arguments,
            // Build commands do not inherit this override automatically in the sandbox.
            environment: ["REFRACT_EXECUTABLE": generator.path],
            inputFiles: inputs,
            // Kotlin/ArkTS must not become SwiftPM target resources. The comment-only
            // Swift anchor orders host compilation after generation/checking instead.
            outputFiles: [anchor]
        )]
    }
}
