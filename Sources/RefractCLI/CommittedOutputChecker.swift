import Foundation

struct CommittedOutputChecker {
    private let writeError: (String) -> Void

    init(writeError: @escaping (String) -> Void) {
        self.writeError = writeError
    }

    func check(outputs: [(directory: String, filename: String, contents: String)]) throws {
        var differences = 0
        var expectedFiles: [URL: Set<String>] = [:]
        for output in outputs {
            let directory = URL(fileURLWithPath: output.directory, isDirectory: true).standardizedFileURL
            let file = directory.appendingPathComponent(output.filename)
            expectedFiles[directory, default: []].insert(output.filename)
            let expected = Data(output.contents.utf8)
            guard let committed = try? Data(contentsOf: file) else {
                writeError("refract: missing committed output \(file.path); run `refract generate` with the same inputs, mapping and output directories, then review and commit it")
                differences += 1
                continue
            }
            if committed != expected {
                writeError("refract: stale committed output \(file.path); run `refract generate` with the same inputs, mapping and output directories, then review and commit the regenerated file")
                differences += 1
            }
        }
        for directory in expectedFiles.keys.sorted(by: { $0.path < $1.path }) {
            guard let expected = expectedFiles[directory] else { continue }
            guard let committed = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ) else { continue }
            for file in committed.sorted(by: { $0.path < $1.path })
                where ["kt", "ets"].contains(file.pathExtension) && !expected.contains(file.lastPathComponent) {
                writeError("refract: unexpected generated output \(file.path); no supplied input produces this file; remove it if it is obsolete, or add its Swift input")
                differences += 1
            }
        }
        guard differences == 0 else {
            throw CLIError.message("check failed: \(differences) committed output(s) are missing, stale or unexpected")
        }
    }
}
