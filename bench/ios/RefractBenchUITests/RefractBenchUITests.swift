import XCTest

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
}
