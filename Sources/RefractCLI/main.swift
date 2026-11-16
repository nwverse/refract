import Foundation
import RefractArkUI
import RefractCompose
import RefractFrontend
import RefractIR
import RefractMapping

enum CLIError: Error { case message(String) }

@main
struct RefractCommand {
    static func main() throws {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch let error as CLIError {
            FileHandle.standardError.write(Data("refract: \(error)\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("refract: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run(arguments: [String]) throws {
        guard let command = arguments.first, command == "generate" || command == "check" else {
            throw CLIError.message("usage: refract generate|check --input <file> --mapping <refract.json> [--android-out <dir> --harmony-out <dir>]")
        }
        var options: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard ["--input", "--mapping", "--android-out", "--harmony-out"].contains(key), index + 1 < arguments.count else {
                throw CLIError.message("unknown or incomplete option: \(key)")
            }
            guard options[key] == nil else { throw CLIError.message("duplicate option: \(key)") }
            options[key] = arguments[index + 1]
            index += 2
        }
        guard let input = options["--input"] else { throw CLIError.message("missing --input") }
        if command == "generate", options["--android-out"] == nil || options["--harmony-out"] == nil {
            throw CLIError.message("generate requires --android-out and --harmony-out")
        }

        let mapping: Mapping
        if let path = options["--mapping"] {
            mapping = try Mapping.load(contentsOf: URL(fileURLWithPath: path))
        } else { mapping = .empty }
        let inputURL = URL(fileURLWithPath: input)
        let unit = Frontend.parse(SourceFile(path: inputURL.lastPathComponent,
                                              contents: try String(contentsOf: inputURL, encoding: .utf8)), mapping: mapping)
        for diagnostic in unit.diagnostics { FileHandle.standardError.write(Data((diagnostic.rendered + "\n").utf8)) }
        guard !unit.hasErrors else { throw CLIError.message("generation stopped because the input has errors") }

        let compose = try ComposeBackend().generate(module: unit.module, mapping: mapping)
        let ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping)
        guard command == "generate" else { return }

        let name = inputURL.deletingPathExtension().lastPathComponent
        let outputs = [(options["--android-out"]!, name + ".kt", compose),
                       (options["--harmony-out"]!, name + ".ets", ark)]
        for (directory, filename, contents) in outputs {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: folder.appendingPathComponent(filename), options: .atomic)
        }
    }
}
