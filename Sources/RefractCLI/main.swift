import Foundation
import RefractArkUI
import RefractCompose
import RefractFrontend
import RefractIR
import RefractMapping

enum CLIError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case let .message(message): message }
    }
}

@main
struct RefractCommand {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch let diagnostic as Diagnostic {
            writeError(diagnostic.rendered)
            exit(1)
        } catch let group as DiagnosticGroup {
            for diagnostic in group.diagnostics { writeError(diagnostic.rendered) }
            exit(1)
        } catch let error as InteropMappingError {
            for diagnostic in error.diagnostics { writeError(diagnostic.rendered) }
            exit(1)
        } catch {
            writeError("refract: \(error)")
            exit(1)
        }
    }

    static func run(arguments: [String]) throws {
        guard let command = arguments.first, command == "generate" || command == "check" else {
            throw CLIError.message("usage: refract generate|check --input <file> [--input <file> ...] [--mapping <refract.json>] [--android-out <dir> --harmony-out <dir>]")
        }
        var inputs: [String] = []
        var options: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard ["--input", "--mapping", "--android-out", "--harmony-out"].contains(key), index + 1 < arguments.count else {
                throw CLIError.message("unknown or incomplete option: \(key)")
            }
            if key == "--input" { inputs.append(arguments[index + 1]) }
            else {
                guard options[key] == nil else { throw CLIError.message("duplicate option: \(key)") }
                options[key] = arguments[index + 1]
            }
            index += 2
        }
        guard !inputs.isEmpty else { throw CLIError.message("missing --input") }
        let mapping: Mapping
        do {
            mapping = try options["--mapping"].map { try Mapping.load(contentsOf: URL(fileURLWithPath: $0)) } ?? .empty
        } catch let diagnostic as Diagnostic {
            writeError(diagnostic.rendered)
            throw CLIError.message("validation stopped because the mapping has errors")
        } catch let error as MappingError {
            for diagnostic in error.diagnostics { writeError(diagnostic.rendered) }
            throw CLIError.message("validation stopped because the mapping has errors")
        }
        if (options["--android-out"] == nil && mapping.android.output.directory.isEmpty)
            || (options["--harmony-out"] == nil && mapping.harmonyOS.output.directory.isEmpty) {
            throw CLIError.message("\(command) requires output directories in refract.json or explicit --android-out and --harmony-out")
        }

        var hasErrors = false
        var units: [TranslationUnit] = []
        var names = Set<String>()
        for input in inputs {
            let url = URL(fileURLWithPath: input)
            let name = url.deletingPathExtension().lastPathComponent
            guard !name.isEmpty, name != ".", name != "..", names.insert(name).inserted else {
                throw CLIError.message("input base filenames must be nonempty and unique: \(input)")
            }
            let unit = Frontend.parse(SourceFile(path: url.lastPathComponent,
                                                  contents: try String(contentsOf: url, encoding: .utf8)), mapping: mapping)
            hasErrors = hasErrors || unit.hasErrors
            unit.diagnostics.forEach { writeError($0.rendered) }
            units.append(unit)
        }
        guard !hasErrors else { throw CLIError.message("validation stopped because the input has errors") }
        for unit in units {
            try LocalizationResourceValidator.validate(module: unit.module, mapping: mapping)
        }

        var outputs: [(directory: String, filename: String, contents: String)] = []
        for unit in units {
            let name = URL(fileURLWithPath: unit.module.sourceFile).deletingPathExtension().lastPathComponent
            var compose: String?
            var ark: String?
            do { compose = try ComposeBackend().generate(module: unit.module, mapping: mapping) }
            catch { hasErrors = true; reportGeneration(error) }
            do { ark = try ArkUIBackend().generate(module: unit.module, mapping: mapping) }
            catch { hasErrors = true; reportGeneration(error) }
            guard let compose, let ark else { continue }
            outputs.append((options["--android-out"] ?? mapping.android.output.directory, name + ".kt", compose))
            outputs.append((options["--harmony-out"] ?? mapping.harmonyOS.output.directory, name + ".ets", ark))
        }
        guard !hasErrors else { throw CLIError.message("generation stopped because validation failed") }
        if command == "check" {
            try CommittedOutputChecker(writeError: writeError).check(outputs: outputs)
            return
        }
        for output in outputs {
            let folder = URL(fileURLWithPath: output.directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(output.contents.utf8).write(to: folder.appendingPathComponent(output.filename), options: .atomic)
        }
    }

    private static func reportGeneration(_ error: Error) {
        if let diagnostic = error as? Diagnostic { writeError(diagnostic.rendered) }
        else if let group = error as? DiagnosticGroup {
            for diagnostic in group.diagnostics { writeError(diagnostic.rendered) }
        } else if let error = error as? InteropMappingError {
            for diagnostic in error.diagnostics { writeError(diagnostic.rendered) }
        } else { writeError("refract: \(error)") }
    }

    private static func writeError(_ text: String) {
        guard let data = (text + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}
