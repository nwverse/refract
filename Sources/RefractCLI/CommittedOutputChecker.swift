import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

private enum CommittedOutputDestinationError: Error {
    case missing
    case nonRegular
}

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
            let committed: Data
            do {
                try requireRegularCommittedOutput(at: file)
                committed = try Data(contentsOf: file)
            } catch CommittedOutputDestinationError.missing {
                writeError("refract: missing committed output \(file.path); run `refract generate` with the same inputs, mapping and output directories, then review and commit it")
                differences += 1
                continue
            } catch CommittedOutputDestinationError.nonRegular {
                writeError("refract: unreadable committed output \(file.path); it is a directory, symbolic link or other non-regular file; remove or relocate it explicitly before checking")
                differences += 1
                continue
            } catch let error as NSError where error.domain == NSCocoaErrorDomain
                && error.code == NSFileReadNoSuchFileError {
                writeError("refract: missing committed output \(file.path); run `refract generate` with the same inputs, mapping and output directories, then review and commit it")
                differences += 1
                continue
            } catch {
                writeError("refract: unreadable committed output \(file.path); fix its permissions or replace a non-regular destination explicitly before checking: \(error.localizedDescription)")
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
                atPath: directory.path
            ) else { continue }
            for filename in committed.sorted()
                where ["kt", "ets"].contains(URL(fileURLWithPath: filename).pathExtension) && !expected.contains(filename) {
                let file = directory.appendingPathComponent(filename)
                writeError("refract: unexpected generated output \(file.path); no supplied input produces this file; remove it if it is obsolete, or add its Swift input")
                differences += 1
            }
        }
        guard differences == 0 else {
            throw CLIError.message("check failed: \(differences) committed output(s) are missing, unreadable, stale or unexpected")
        }
    }

    private func requireRegularCommittedOutput(at file: URL) throws {
        var info = stat()
        guard file.path.withCString({ lstat($0, &info) }) == 0 else {
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            guard error.code == ENOENT else { throw error }
            throw CommittedOutputDestinationError.missing
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw CommittedOutputDestinationError.nonRegular
        }
    }
}
