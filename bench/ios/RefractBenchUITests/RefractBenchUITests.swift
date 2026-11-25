import CoreFoundation
import XCTest

@MainActor
private enum TraceHandshake {
    static let tracedIterations = 2...30

    static func tracedIteration(_ value: String?) -> Int? {
        guard let value, let iteration = Int(value) else { return nil }
        return tracedIterations.contains(iteration) ? iteration : nil
    }

    static func write(_ payload: [String: Any], named name: String, in directory: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let destination = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw NSError(domain: "RefractBench.TraceHandshake", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Refusing to replace \(name)"])
        }
        try data.write(to: destination, options: .withoutOverwriting)
    }

    static func ready(in directory: URL, expected: [String: Any],
                      name: String = "recorder-ready.json") -> [String: Any]? {
        let path = directory.appendingPathComponent(name)
        if name == "native-process.json" || name == "native-completion.json" || name == "begin.json" {
            let stem = name.dropLast(".json".count)
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path),
                  entries.filter({ $0.hasPrefix(stem) && $0.hasSuffix(".json") }).sorted() == [name] else {
                XCTFail("Missing or ambiguous \(name) native packet")
                return nil
            }
        }
        guard let data = try? Data(contentsOf: path),
              let packet = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for (key, value) in expected {
            if key == "finalSamples" || key == "nativeResources" {
                // JSON round-trips produce nested Any containers. Compare their
                // canonical bytes instead of weakening the scalar comparator.
                guard let actual = packet[key], JSONSerialization.isValidJSONObject(actual),
                      JSONSerialization.isValidJSONObject(value),
                      canonicalJSON(actual) == canonicalJSON(value) else {
                    XCTFail("Stale or mismatched recorder \(key)")
                    return nil
                }
            } else if !isEqual(packet[key], value) {
                XCTFail("Stale or mismatched recorder \(key)")
                return nil
            }
        }
        return packet
    }

    static func firstDisplay(in completionPacket: [String: Any]) throws -> [String: String] {
        guard let firstDisplay = completionPacket["firstDisplay"] as? [String: String],
              Set(firstDisplay.keys) == ["clock", "timestamp"],
              firstDisplay["clock"] == "CACurrentMediaTime",
              let text = firstDisplay["timestamp"],
              let timestamp = Double(text),
              String(timestamp) == text, timestamp.isFinite, timestamp > 0 else {
            XCTFail("Startup requires finite first-display evidence from the attached native process")
            throw NSError(domain: "RefractBench.TraceHandshake", code: 2)
        }
        return firstDisplay
    }

    static func finalSamples(in completionPacket: [String: Any], revision: String,
                             variant: String, scenario: String,
                             iteration: Int, pid: Int) throws -> [String: Any] {
        let expectedKeys: Set<String> = ["schema", "session", "sourceRevision", "variant", "scenario",
                                         "iteration", "pid", "completedIterations", "recordedIteration",
                                         "frameIntervalMs", "iterationByFrame"]
        guard let samples = completionPacket["finalSamples"] as? [String: Any],
              Set(samples.keys) == expectedKeys,
              samples["schema"] as? Int == 1, samples["session"] as? Int == 1,
              samples["sourceRevision"] as? String == revision,
              samples["variant"] as? String == variant, samples["scenario"] as? String == scenario,
              samples["iteration"] as? Int == iteration, samples["pid"] as? Int == pid,
              samples["completedIterations"] as? Int == 1,
              samples["recordedIteration"] as? Int == iteration,
              let intervals = samples["frameIntervalMs"] as? [Double],
              let tags = samples["iterationByFrame"] as? [Int],
              !intervals.isEmpty, intervals.count <= 4096, intervals.count == tags.count,
              intervals.allSatisfy({ $0.isFinite && $0 > 0 }),
              tags.allSatisfy({ $0 == iteration }) else {
            XCTFail("Final native samples must match this iteration and contain finite positive display intervals")
            throw NSError(domain: "RefractBench.TraceHandshake", code: 3)
        }
        return samples
    }

    static func nativeResources(in completionPacket: [String: Any], revision: String,
                                variant: String, scenario: String,
                                iteration: Int, pid: Int) throws -> [[String: Any]] {
        guard let resources = completionPacket["nativeResources"] as? [[String: Any]],
              resources.count == 2, let resourcesData = canonicalJSON(resources),
              resourcesData.count <= 1024 * 1024 else {
            XCTFail("Native completion requires exactly one memory and one installed-app snapshot")
            throw NSError(domain: "RefractBench.TraceHandshake", code: 4)
        }
        let identityKeys: Set<String> = ["schema", "session", "sourceRevision", "variant", "scenario", "iteration",
                                         "metric", "bytes", "unit", "definition"]
        for resource in resources {
            guard isInteger(resource["schema"], equalTo: 1), isInteger(resource["session"], equalTo: 1),
                  resource["sourceRevision"] as? String == revision,
                  resource["variant"] as? String == variant, resource["scenario"] as? String == scenario,
                  isInteger(resource["iteration"], equalTo: iteration), resource["unit"] as? String == "bytes",
                  let bytes = integer(resource["bytes"]), bytes > 0,
                  let metric = resource["metric"] as? String else {
                XCTFail("Native resource identity and positive bytes must match this exact iteration")
                throw NSError(domain: "RefractBench.TraceHandshake", code: 4)
            }
            switch metric {
            case "residentMemoryBytes":
                guard Set(resource.keys) == identityKeys.union(["pid"]),
                      integer(resource["pid"]) == pid,
                      resource["definition"] as? String == "task_info.TASK_VM_INFO.resident_size" else {
                    XCTFail("Native resident memory requires the attached PID and Darwin resident_size")
                    throw NSError(domain: "RefractBench.TraceHandshake", code: 4)
                }
            case "installedBinaryBytes":
                guard Set(resource.keys) == identityKeys.union(["bundle", "files"]),
                      resource["bundle"] as? String == "RefractBench.app",
                      resource["definition"] as? String == "Bundle.main.regular-file-bytes",
                      let files = resource["files"] as? [[String: Any]],
                      !files.isEmpty, files.count <= 10000 else {
                    XCTFail("Installed binary bytes require the actual app bundle's regular-file inventory")
                    throw NSError(domain: "RefractBench.TraceHandshake", code: 4)
                }
                var total = 0
                for file in files {
                    guard Set(file.keys) == ["path", "bytes", "sha256"],
                          let path = file["path"] as? String,
                          !path.isEmpty, path.count <= 4096, !path.hasPrefix("/"), !path.contains("\\"),
                          !path.contains("\0"), !path.unicodeScalars.contains(where: { $0.value < 0x20 }),
                          !path.split(separator: "/", omittingEmptySubsequences: false)
                              .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                          let size = integer(file["bytes"]), size >= 0,
                          let digest = file["sha256"] as? String,
                          digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                        XCTFail("Installed app file identities must be bounded, relative and checksummed")
                        throw NSError(domain: "RefractBench.TraceHandshake", code: 4)
                    }
                    let (next, overflow) = total.addingReportingOverflow(size)
                    guard !overflow else {
                        XCTFail("Installed app byte count overflowed")
                        throw NSError(domain: "RefractBench.TraceHandshake", code: 4)
                    }
                    total = next
                }
                guard total == bytes, Set(files.compactMap({ $0["path"] as? String })).count == files.count else {
                    XCTFail("Installed app bytes must equal their unique regular-file sum")
                    throw NSError(domain: "RefractBench.TraceHandshake", code: 4)
                }
            default:
                XCTFail("Unsupported native resource metric")
                throw NSError(domain: "RefractBench.TraceHandshake", code: 4)
            }
        }
        guard Set(resources.compactMap({ $0["metric"] as? String })) ==
                ["residentMemoryBytes", "installedBinaryBytes"] else {
            XCTFail("Native resource metrics must be unique")
            throw NSError(domain: "RefractBench.TraceHandshake", code: 4)
        }
        return resources
    }

    private static func integer(_ value: Any?) -> Int? {
        // NSNumber bridges JSON booleans to Int. Reject them before conversion.
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        #if os(Linux)
        // swift-corelibs-foundation does not bridge NSNumber to CFNumber.
        // Its ObjC type encoding distinguishes floating-point JSON numbers.
        if ["f", "d"].contains(String(cString: number.objCType)) { return nil }
        #else
        if CFNumberIsFloatType(number) { return nil }
        #endif
        return Int(exactly: number)
    }

    private static func isInteger(_ value: Any?, equalTo expected: Int) -> Bool {
        integer(value) == expected
    }

    static func canonicalJSON(_ value: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return nil
        }
        return data
    }

    private static func isEqual(_ lhs: Any?, _ rhs: Any) -> Bool {
        switch rhs {
        case let value as String: return lhs as? String == value
        case let value as Int: return lhs as? Int == value
        case let value as [String: String]: return lhs as? [String: String] == value
        default: return false
        }
    }
}

@MainActor
final class RefractBenchUITests: XCTestCase {
    func testGeneratedColdStart() {
        launchMetric("generated")
    }

    func testReferenceColdStart() {
        launchMetric("reference")
    }

    func testGeneratedScroll() {
        runScenario("scroll", variant: "generated")
    }

    func testReferenceScroll() {
        runScenario("scroll", variant: "reference")
    }

    func testGeneratedStateUpdate() {
        runScenario("stateUpdate", variant: "generated")
    }

    func testReferenceStateUpdate() {
        runScenario("stateUpdate", variant: "reference")
    }

    func testGeneratedScrollTrace() throws {
        try runTracedIteration("scroll", variant: "generated")
    }

    func testReferenceScrollTrace() throws {
        try runTracedIteration("scroll", variant: "reference")
    }

    func testGeneratedStateUpdateTrace() throws {
        try runTracedIteration("stateUpdate", variant: "generated")
    }

    func testReferenceStateUpdateTrace() throws {
        try runTracedIteration("stateUpdate", variant: "reference")
    }

    func testGeneratedStartupTrace() throws {
        try runTracedIteration("startup", variant: "generated")
    }

    func testReferenceStartupTrace() throws {
        try runTracedIteration("startup", variant: "reference")
    }

    private func launchMetric(_ variant: String) {
        let options = XCTMeasureOptions()
        options.iterationCount = 30
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            let application = XCUIApplication()
            application.launchEnvironment = [
                "REFRACT_BENCH_REVISION": ProcessInfo.processInfo.environment["REFRACT_BENCH_REVISION"] ?? "",
                "REFRACT_BENCH_VARIANT": variant,
                "REFRACT_BENCH_SCENARIO": "startup",
            ]
            application.launch()
            XCTAssertTrue(application.staticTexts["Native settings"].waitForExistence(timeout: 20))
            // Scene activation captures a first-display timestamp, not a test-process stopwatch.
            application.terminate()
        }
    }

    private func runScenario(_ scenario: String, variant: String) {
        let application = XCUIApplication()
        application.launchEnvironment = [
            "REFRACT_BENCH_VARIANT": variant,
            "REFRACT_BENCH_SCENARIO": scenario,
        ]
        application.launch()
        XCTAssertTrue(application.staticTexts["Setting 0"].waitForExistence(timeout: 20))
        // The app owns the identical native input script for both variants.
        // The harness records completion; no time around a test-runner command
        // is substituted for native display or frame evidence.
        let completion = application.staticTexts["\(variant) \(scenario) complete 30"]
        XCTAssertTrue(completion.waitForExistence(timeout: 180))
        application.terminate()
    }

    private func runTracedIteration(_ scenario: String, variant: String) throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["REFRACT_BENCH_TRACE_CONTROL"] != nil else {
            throw XCTSkip("Per-iteration capture requires the explicit Instruments runner")
        }
        guard let iterationValue = environment["REFRACT_BENCH_TRACE_ITERATION"],
              let iteration = TraceHandshake.tracedIteration(iterationValue),
              let controlValue = environment["REFRACT_BENCH_TRACE_CONTROL"] else {
            XCTFail("An exact iteration and new control directory are required")
            return
        }
        let control = URL(fileURLWithPath: controlValue, isDirectory: true)
        let application = XCUIApplication()
        application.launchEnvironment = [
            "REFRACT_BENCH_REVISION": environment["REFRACT_BENCH_REVISION"] ?? "",
            "REFRACT_BENCH_VARIANT": variant,
            "REFRACT_BENCH_SCENARIO": scenario,
            "REFRACT_BENCH_ITERATION": iterationValue,
            "REFRACT_BENCH_TRACE_CONTROL": controlValue,
        ]
        // Only the existing single traced launch consumes iterationRange().
        // Its legacy non-traced loop remains the unchanged 0..<30 identity sequence.
        if let iteration = TraceHandshake.tracedIteration(environment["REFRACT_BENCH_TRACE_ITERATION"]),
           environment["REFRACT_BENCH_TRACE_CONTROL"] != nil {
            application.launchEnvironment["REFRACT_BENCH_ITERATION"] = String(iteration)
        }
        application.launch()
        defer { application.terminate() }
        guard application.staticTexts["Setting 0"].waitForExistence(timeout: 20),
              application.staticTexts["\(variant) \(scenario) waiting"]
                  .waitForExistence(timeout: 20) else {
            XCTFail("The exact app iteration did not become ready")
            application.terminate()
            return
        }
        guard application.state == .runningForeground else {
            XCTFail("The selected native app is not running in the foreground")
            return
        }
        let revision = environment["REFRACT_BENCH_REVISION"] ?? ""
        guard !revision.isEmpty else {
            XCTFail("The exact committed source revision is required")
            return
        }
        let identityError = application.staticTexts[
            "refract_benchmark_trace_identity_error"]
        let expectedIdentity: [String: Any] = [
            "schema": 1, "session": 1, "revision": revision, "variant": variant, "scenario": scenario,
            "iteration": iteration, "process": "running", "state": "ready",
        ]
        let processReady = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                TraceHandshake.ready(in: control, expected: expectedIdentity,
                                     name: "native-process.json") != nil
            }, object: nil)
        guard XCTWaiter.wait(for: [processReady], timeout: 20) == .completed else {
            XCTFail("The app did not publish supported native process identity: \(identityError.label)")
            return
        }
        guard let processPacket = TraceHandshake.ready(in: control, expected: expectedIdentity,
                                                       name: "native-process.json"),
              let pid = processPacket["pid"] as? Int, pid > 0 else {
            XCTFail("The native process identity must contain one positive PID")
            return
        }
        let packet: [String: Any] = [
            "schema": 1, "session": 1, "revision": revision, "variant": variant, "scenario": scenario,
            "iteration": iteration, "pid": pid, "process": "running", "state": "ready",
        ]
        do {
            try TraceHandshake.write(packet, named: "request.json", in: control)
            let readyText = application.staticTexts["\(variant) \(scenario) ready"]
            guard readyText.waitForExistence(timeout: 65) else {
                XCTFail("The distinct Instruments recorder did not become ready")
                return
            }
            let begin = application.buttons["refract_benchmark_begin_iteration"]
            guard begin.waitForExistence(timeout: 5), begin.isHittable else {
                XCTFail("The exact app iteration has no start boundary")
                return
            }
            begin.tap()
            var expectedBegin = packet
            expectedBegin["state"] = "begin"
            let nativeBegin = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    TraceHandshake.ready(in: control, expected: expectedBegin, name: "begin.json") != nil
                }, object: nil)
            guard XCTWaiter.wait(for: [nativeBegin], timeout: 10) == .completed else {
                XCTFail("The app did not acknowledge its native Begin boundary: \(identityError.label)")
                return
            }
            let completionText = "\(variant) \(scenario) complete 1"
            let completion = application.staticTexts[completionText]
            guard completion.waitForExistence(timeout: 180), application.state == .runningForeground else {
                XCTFail("The exact native iteration did not complete on the attached process")
                application.terminate()
                return
            }
            var expectedIdentity = packet
            expectedIdentity["state"] = "complete"
            expectedIdentity["completion"] = completionText
            expectedIdentity["pid"] = pid
            let nativeCompletion = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    TraceHandshake.ready(in: control, expected: expectedIdentity,
                                         name: "native-completion.json") != nil
                }, object: nil)
            guard XCTWaiter.wait(for: [nativeCompletion], timeout: 30) == .completed else {
                XCTFail("The native completion identity or PID did not become ready: \(identityError.label)")
                return
            }
            guard let completionPacket = TraceHandshake.ready(
                    in: control, expected: expectedIdentity, name: "native-completion.json"),
                  let completionPID = completionPacket["pid"] as? Int, completionPID == pid else {
                XCTFail("The native completion identity or PID does not match the attached process")
                return
            }
            let firstDisplay = scenario == "startup" ? try TraceHandshake.firstDisplay(in: completionPacket) : nil
            if scenario != "startup" {
                _ = try TraceHandshake.finalSamples(in: completionPacket, revision: revision,
                                                    variant: variant, scenario: scenario,
                                                    iteration: iteration, pid: pid)
            }
            let nativeResources = try TraceHandshake.nativeResources(
                in: completionPacket, revision: revision, variant: variant,
                scenario: scenario, iteration: iteration, pid: pid)
            let nativeData = try Data(contentsOf: control.appendingPathComponent("native-completion.json"))
            guard let nativePacket = try JSONSerialization.jsonObject(with: nativeData) as? [String: Any],
                  let nativeResourceData = TraceHandshake.canonicalJSON(nativePacket["nativeResources"] as Any),
                  let forwardedData = TraceHandshake.canonicalJSON(completionPacket["nativeResources"] as Any),
                  nativeResourceData == forwardedData else {
                XCTFail("Forwarded native resource packets differ")
                throw NSError(domain: "RefractBench.TraceHandshake", code: 4)
            }
            try TraceHandshake.write(completionPacket, named: "completion.json", in: control)
            var expectedFinished = completionPacket
            expectedFinished["state"] = "recorder-finished"
            expectedFinished["nativeResources"] = nativeResources
            if let firstDisplay {
                // Replace the JSON dictionary with its already validated typed
                // strings; the scalar comparator deliberately rejects Any dictionaries.
                expectedFinished["firstDisplay"] = firstDisplay
            }
            let finished = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    TraceHandshake.ready(in: control, expected: expectedFinished,
                                         name: "recorder-finished.json") != nil
                }, object: nil)
            guard XCTWaiter.wait(for: [finished], timeout: 30) == .completed else {
                XCTFail("Instruments did not finish and preserve this exact iteration")
                return
            }
        } catch {
            XCTFail("Trace handshake failed: \(error.localizedDescription)")
        }
    }
}
