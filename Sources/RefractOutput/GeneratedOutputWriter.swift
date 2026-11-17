import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public struct GeneratedOutput: Equatable, Sendable {
    public let directory: String
    public let filename: String
    public let contents: String

    public init(directory: String, filename: String, contents: String) {
        self.directory = directory
        self.filename = filename
        self.contents = contents
    }
}

public enum GeneratedOutputError: Error, CustomStringConvertible, Equatable {
    case message(String)
    case cleanup(String)
    case rollback(String)

    public var description: String {
        switch self {
        case let .message(message), let .cleanup(message), let .rollback(message): message
        }
    }
}

/// Publishes a complete invocation under per-directory locks, with rollback on ordinary I/O failures.
/// Cross-directory atomic replacement is not available on the supported platforms; see docs/cli.md.
public enum GeneratedOutputWriter {
    public static func commit(_ outputs: [GeneratedOutput]) throws {
        try commit(outputs, lockTimeout: 30, lockPollInterval: 0.05)
    }

    static func commit(_ outputs: [GeneratedOutput], lockTimeout: TimeInterval,
                       lockPollInterval: TimeInterval, beforeSecondReplacement: (() throws -> Void)? = nil) throws {
        let files = FileManager.default
        let plans = try outputs.map { output in
            guard !output.directory.isEmpty, !output.filename.isEmpty,
                  output.filename != ".", output.filename != "..",
                  !output.filename.contains("/"), !output.filename.contains("\\"),
                  !output.filename.contains("\0") else {
                throw GeneratedOutputError.message("Invalid generated output name `\(output.filename)`; provide a nonempty filename in a configured output directory.")
            }
            let directory = URL(fileURLWithPath: output.directory, isDirectory: true).standardizedFileURL
            let destination = URL(fileURLWithPath: output.directory).appendingPathComponent(output.filename)
            let lockDirectory = directory.resolvingSymlinksInPath()
            let lock = lockDirectory.appendingPathComponent(".refract-generate.lock", isDirectory: true)
            return Plan(directory: directory, destination: destination, lockDirectory: lockDirectory, lock: lock,
                        contents: Data(output.contents.utf8))
        }
        let destinations = Dictionary(grouping: plans, by: { $0.destination.resolvingSymlinksInPath().path })
        if let collision = destinations.first(where: { $0.value.count > 1 })?.value {
            throw GeneratedOutputError.message("Generated output paths collide at `\(collision[0].destination.path)`; give each input a unique base filename and use separate output directories.")
        }

        let directories = Dictionary(grouping: plans, by: { $0.directory.resolvingSymlinksInPath().path })
        var transaction = Transaction()
        defer { transaction.removeCreatedDirectories() }
        do {
            for (_, group) in directories.sorted(by: { $0.key < $1.key }) {
                let directory = group[0].lockDirectory
                var isDirectory: ObjCBool = false
                if files.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
                    guard isDirectory.boolValue else {
                        throw GeneratedOutputError.message("Cannot write generated output directory `\(directory.path)` because it is not a directory; choose a writable directory.")
                    }
                } else {
                    try files.createDirectory(at: directory, withIntermediateDirectories: true)
                    transaction.createdDirectories.append(directory)
                }
                let lock = group[0].lock
                try acquire(lock: lock, timeout: lockTimeout, pollInterval: lockPollInterval)
                transaction.locks.append(lock)
                for plan in group {
                    guard files.destinationIsReplaceable(plan.destination) else {
                        throw GeneratedOutputError.message("Cannot replace generated output `\(plan.destination.path)` because it is a directory, symbolic link or other non-regular file; remove or relocate it explicitly.")
                    }
                    if files.fileExists(atPath: plan.destination.path) {
                        plan.backup = plan.lockDirectory.appendingPathComponent(".refract-backup-\(UUID().uuidString)")
                        try files.copyItem(at: plan.destination, to: plan.backup!)
                    }
                    plan.staged = plan.lockDirectory.appendingPathComponent(".refract-temporary-\(UUID().uuidString)")
                    try plan.contents.write(to: plan.staged!)
                }
            }
            for (index, plan) in plans.enumerated() {
                if index == 1 { try beforeSecondReplacement?() }
                try files.replace(plan.staged!, at: plan.destination)
                plan.staged = nil
                plan.replaced = true
            }
        } catch {
            let rollbackError = transaction.rollback(plans: plans)
            if let rollbackError {
                throw GeneratedOutputError.rollback("\(error) The previous outputs could not be fully restored: \(rollbackError) Inspect the reported paths before regenerating.")
            }
            throw error
        }
        var cleanupErrors: [String] = []
        for plan in plans {
            if let backup = plan.backup {
                do {
                    try files.removeItem(at: backup)
                    plan.backup = nil
                } catch { cleanupErrors.append("\(backup.path): \(error.localizedDescription)") }
            }
        }
        let lockError = transaction.releaseLocks()
        guard cleanupErrors.isEmpty, lockError == nil else {
            let details = (cleanupErrors + [lockError].compactMap { $0 }).joined(separator: "; ")
            throw GeneratedOutputError.cleanup("Generated outputs were published, but temporary-file cleanup failed: \(details) Remove only the named temporary paths after checking that no other generator is using them.")
        }
    }

    private static func acquire(lock: URL, timeout: TimeInterval, pollInterval: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            do {
                try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
                return
            } catch CocoaError.fileWriteFileExists {
                if Date() >= deadline {
                    throw GeneratedOutputError.message("Timed out waiting to generate into `\(lock.deletingLastPathComponent().path)`; another generation holds `.refract-generate.lock`. Retry after it finishes, or remove a stale lock only after confirming that no generator is running.")
                }
                Thread.sleep(forTimeInterval: pollInterval)
            } catch {
                throw GeneratedOutputError.message("Cannot create the generation lock `\(lock.path)`; choose a writable output directory. Underlying error: \(error.localizedDescription)")
            }
        }
    }

    private final class Plan {
        let directory: URL
        let destination: URL
        let lockDirectory: URL
        let lock: URL
        let contents: Data
        var staged: URL?
        var backup: URL?
        var replaced = false

        init(directory: URL, destination: URL, lockDirectory: URL, lock: URL, contents: Data) {
            self.directory = directory
            self.destination = destination
            self.lockDirectory = lockDirectory
            self.lock = lock
            self.contents = contents
        }
    }

    private struct Transaction {
        var locks: [URL] = []
        var createdDirectories: [URL] = []

        mutating func releaseLocks() -> String? {
            var errors: [String] = []
            for lock in locks.reversed() {
                do { try FileManager.default.removeItem(at: lock) }
                catch { errors.append("\(lock.path): \(error.localizedDescription)") }
            }
            locks.removeAll()
            return errors.isEmpty ? nil : errors.joined(separator: "; ")
        }

        func removeCreatedDirectories() {
            for directory in createdDirectories.reversed() {
                guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path), contents.isEmpty else { continue }
                try? FileManager.default.removeItem(at: directory)
            }
        }

        func rollback(plans: [Plan]) -> String? {
            var errors: [String] = []
            for plan in plans.reversed() {
                do {
                    if let staged = plan.staged { try FileManager.default.removeItem(at: staged) }
                    if let backup = plan.backup {
                        if plan.replaced {
                            if FileManager.default.fileExists(atPath: plan.destination.path) {
                                try FileManager.default.removeItem(at: plan.destination)
                            }
                            try FileManager.default.moveItem(at: backup, to: plan.destination)
                        } else {
                            try FileManager.default.removeItem(at: backup)
                        }
                    } else if plan.replaced, FileManager.default.fileExists(atPath: plan.destination.path) {
                        try FileManager.default.removeItem(at: plan.destination)
                    }
                } catch {
                    errors.append("\(plan.destination.path): \(error.localizedDescription)")
                }
            }
            for lock in locks.reversed() {
                do { try FileManager.default.removeItem(at: lock) }
                catch { errors.append("\(lock.path): \(error.localizedDescription)") }
            }
            return errors.isEmpty ? nil : errors.joined(separator: "; ")
        }
    }
}

private extension FileManager {
    func replace(_ staged: URL, at destination: URL) throws {
        let result = staged.path.withCString { source in
            destination.path.withCString { target in
                rename(source, target)
            }
        }
        guard result == 0 else {
            throw GeneratedOutputError.message("Could not replace generated output `\(destination.path)` (system error \(errno)); verify the destination is writable. Previously replaced outputs will be restored.")
        }
    }

    func destinationIsReplaceable(_ url: URL) -> Bool {
        var info = stat()
        guard url.path.withCString({ lstat($0, &info) }) == 0 else { return errno == ENOENT }
        return (info.st_mode & S_IFMT) == S_IFREG
    }
}
