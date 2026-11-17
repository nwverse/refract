import Foundation
import Testing
@testable import RefractOutput

@Suite("Generated output transaction")
struct GeneratedOutputWriterTests {
    @Test func failedReplacementRestoresCommittedFilesAndCleansTemporaryFiles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let android = root.appendingPathComponent("android")
        let harmony = root.appendingPathComponent("harmony")
        try FileManager.default.createDirectory(at: android, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: harmony, withIntermediateDirectories: true)
        try write("old Kotlin", to: android.appendingPathComponent("Screen.kt"))
        try write("old ArkTS", to: harmony.appendingPathComponent("Screen.ets"))
        let outputs = [
            GeneratedOutput(directory: android.path, filename: "Screen.kt", contents: "new Kotlin"),
            GeneratedOutput(directory: harmony.path, filename: "Screen.ets", contents: "new ArkTS"),
        ]
        #expect(throws: TestError.injected) {
            try GeneratedOutputWriter.commit(outputs, lockTimeout: 0.1, lockPollInterval: 0.001) {
                throw TestError.injected
            }
        }
        #expect(try contents(of: android.appendingPathComponent("Screen.kt")) == "old Kotlin")
        #expect(try contents(of: harmony.appendingPathComponent("Screen.ets")) == "old ArkTS")
        #expect(try FileManager.default.contentsOfDirectory(atPath: android.path) == ["Screen.kt"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: harmony.path) == ["Screen.ets"])
    }

    @Test func failedReplacementRemovesNewFilesAndRestoresOldFiles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("Existing.kt")
        let added = root.appendingPathComponent("Added.kt")
        try write("old", to: existing)
        let outputs = [
            GeneratedOutput(directory: root.path, filename: "Existing.kt", contents: "new"),
            GeneratedOutput(directory: root.path, filename: "Added.kt", contents: "new"),
        ]
        #expect(throws: TestError.injected) {
            try GeneratedOutputWriter.commit(outputs, lockTimeout: 0.1, lockPollInterval: 0.001) {
                throw TestError.injected
            }
        }
        #expect(try contents(of: existing) == "old")
        #expect(!FileManager.default.fileExists(atPath: added.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["Existing.kt"])
    }

    @Test func failureBeforeReplacementPreservesAllFilesAndUnrelatedOutputs() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let android = root.appendingPathComponent("android")
        let harmony = root.appendingPathComponent("harmony")
        let blocked = harmony.path + "/Screen.ets"
        try FileManager.default.createDirectory(atPath: blocked, withIntermediateDirectories: true)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: blocked, isDirectory: &isDirectory) && isDirectory.boolValue)
        try "keep this".write(toFile: blocked + "/keep.txt", atomically: true, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: blocked + "/keep.txt"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: blocked) == ["keep.txt"])
        let error = #expect(throws: GeneratedOutputError.self) {
            try GeneratedOutputWriter.commit([
                GeneratedOutput(directory: android.path, filename: "Screen.kt", contents: "Kotlin"),
                GeneratedOutput(directory: harmony.path, filename: "Screen.ets", contents: "ArkTS"),
            ])
        }
        #expect(error?.description.contains("Screen.ets") == true)
        #expect(try String(contentsOfFile: blocked + "/keep.txt", encoding: .utf8) == "keep this")
        #expect(!FileManager.default.fileExists(atPath: android.path))
    }

    @Test func symbolicLinkDestinationIsNotFollowedOrRemoved() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("handwritten.kt")
        let link = root.appendingPathComponent("Screen.kt")
        try write("keep", to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let error = #expect(throws: GeneratedOutputError.self) {
            try GeneratedOutputWriter.commit([
                GeneratedOutput(directory: root.path, filename: "Screen.kt", contents: "generated"),
            ])
        }
        #expect(error?.description.contains("symbolic link") == true)
        #expect(try contents(of: target) == "keep")
        #expect(FileManager.default.fileExists(atPath: link.path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    }

    @Test func lockFailureDoesNotLeaveAnEarlierNewOutputDirectory() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let android = root.appendingPathComponent("android")
        let harmony = root.appendingPathComponent("harmony")
        try FileManager.default.createDirectory(at: harmony, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: harmony.appendingPathComponent(".refract-generate.lock"), withIntermediateDirectories: false)
        #expect(throws: GeneratedOutputError.self) {
            try GeneratedOutputWriter.commit([
                GeneratedOutput(directory: android.path, filename: "Screen.kt", contents: "Kotlin"),
                GeneratedOutput(directory: harmony.path, filename: "Screen.ets", contents: "ArkTS"),
            ], lockTimeout: 0.01, lockPollInterval: 0.001)
        }
        #expect(!FileManager.default.fileExists(atPath: android.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: harmony.path) == [".refract-generate.lock"])
    }

    @Test func staleLockReturnsActionableErrorAndRetriesAfterRelease() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".refract-generate.lock"), withIntermediateDirectories: true)
        let output = GeneratedOutput(directory: root.path, filename: "Screen.kt", contents: "Kotlin")
        let error = #expect(throws: GeneratedOutputError.self) {
            try GeneratedOutputWriter.commit([output], lockTimeout: 0.01, lockPollInterval: 0.001)
        }
        #expect(error?.description.contains(".refract-generate.lock") == true)
        #expect(error?.description.contains("no generator is running") == true)
        try FileManager.default.removeItem(at: root.appendingPathComponent(".refract-generate.lock"))
        try GeneratedOutputWriter.commit([output], lockTimeout: 0.1, lockPollInterval: 0.001)
        #expect(try contents(of: root.appendingPathComponent("Screen.kt")) == "Kotlin")
    }

    @Test func concurrentWritersLeaveOneCoherentGenerationWithoutTemporaryFiles() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = GeneratedOutput(directory: root.path, filename: "Screen.kt", contents: "")
        try GeneratedOutputWriter.commit([output])
        let lock = root.appendingPathComponent(".refract-generate.lock")
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        try write("first", to: root.appendingPathComponent(".refract-temporary-fixture"))
        try write("committed", to: root.appendingPathComponent("Screen.kt"))
        let waiting = Task {
            try GeneratedOutputWriter.commit([
                GeneratedOutput(directory: root.path, filename: "Screen.kt", contents: "next"),
            ], lockTimeout: 5, lockPollInterval: 0.001)
        }
        try FileManager.default.removeItem(at: lock)
        try await waiting.value
        #expect(try contents(of: root.appendingPathComponent("Screen.kt")) == "next")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == [".refract-temporary-fixture", "Screen.kt"])
    }

    @Test(arguments: [
        [GeneratedOutput(directory: "same", filename: "Screen.kt", contents: "Kotlin"),
         GeneratedOutput(directory: "same", filename: "Screen.kt", contents: "other")],
        [GeneratedOutput(directory: "same", filename: "../Screen.kt", contents: "escape")],
    ])
    func unsafeOrDuplicateDestinationsAreRejected(outputs: [GeneratedOutput]) throws {
        #expect(throws: GeneratedOutputError.self) { try GeneratedOutputWriter.commit(outputs) }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("refract-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws { try Data(text.utf8).write(to: url) }
    private func contents(of url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
}

private enum TestError: Error, Equatable { case injected }
