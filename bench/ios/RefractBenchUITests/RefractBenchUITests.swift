import XCTest

@MainActor
private enum TraceHandshake {
    static let iterationCount = 30

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
        for (key, value) in expected where !isEqual(packet[key], value) {
            XCTFail("Stale or mismatched recorder \(key)")
            return nil
        }
        return packet
    }

    private static func isEqual(_ lhs: Any?, _ rhs: Any) -> Bool {
        switch rhs {
        case let value as String: return lhs as? String == value
        case let value as Int: return lhs as? Int == value
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
              let iteration = Int(iterationValue), (0..<TraceHandshake.iterationCount).contains(iteration),
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
            if scenario == "startup" {
                guard let firstDisplay = completionPacket["firstDisplay"] as? [String: Any],
                      Set(firstDisplay.keys) == ["clock", "timestamp"],
                      firstDisplay["clock"] as? String == "CACurrentMediaTime",
                      let timestamp = firstDisplay["timestamp"] as? Double,
                      timestamp.isFinite, timestamp > 0 else {
                    XCTFail("Startup requires finite first-display evidence from the attached native process")
                    return
                }
            }
            try TraceHandshake.write(completionPacket, named: "completion.json", in: control)
            var expectedFinished = completionPacket
            expectedFinished["state"] = "recorder-finished"
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
