import QuartzCore

/// App-owned native sampling only; it does not measure wall-clock UI gestures
/// and does not pretend that display-link callbacks are CPU frame times.
@MainActor
final class BenchmarkDisplayRecorder: ObservableObject {
    static let shared = BenchmarkDisplayRecorder()
    // #219 has exactly thirty traced identities: 2 through 30 inclusive.
    static let tracedIterations = 2...30

    private let framesKey = "refract.bench.frames.v1"
    private var link: CADisplayLink?
    private var active = false
    private(set) var firstDisplay: CFTimeInterval?
    private var frames: [CFTimeInterval] = []
    private var iterations: [Int] = []
    private var completedIterations = 0
    private var recordedIteration = 0
    @Published private(set) var completion: (variant: String, scenario: String, count: Int)?
    @Published var beginSelectedIteration = false
    private var selectedIteration: Int? {
        guard let value = ProcessInfo.processInfo.environment["REFRACT_BENCH_ITERATION"] else { return nil }
        return Int(value)
    }
    var revision: String { ProcessInfo.processInfo.environment["REFRACT_BENCH_REVISION"] ?? "" }
    private var variant: String { ProcessInfo.processInfo.environment["REFRACT_BENCH_VARIANT"] ?? "" }
    private var scenario: String { ProcessInfo.processInfo.environment["REFRACT_BENCH_SCENARIO"] ?? "" }

    func prepareForLaunch() {
        active = ProcessInfo.processInfo.environment["REFRACT_BENCH_SCENARIO"] == "startup"
        firstDisplay = nil
        frames = []
        completedIterations = 0
        recordedIteration = 0
        completion = nil
        beginSelectedIteration = false
        iterations = []
        startLinkIfNeeded()
    }

    func sceneBecameActive() {
        guard active, firstDisplay == nil else { return }
        firstDisplay = CACurrentMediaTime()
        persist()
    }

    func completeStartup(iteration: Int) -> CFTimeInterval? {
        guard active, scenario == "startup", selectedIteration == iteration,
              Self.tracedIterations.contains(iteration), let firstDisplay, firstDisplay.isFinite, firstDisplay > 0,
              !revision.isEmpty, !variant.isEmpty else { return nil }
        completedIterations = 1
        recordedIteration = iteration
        active = false
        link?.isPaused = true
        completion = (variant, scenario, 1)
        persist()
        return firstDisplay
    }

    func beginScenario(_ scenario: String) {
        guard scenario == "scroll" || scenario == "stateUpdate" else { return }
        active = true
        frames = []
        completedIterations = 0
        recordedIteration = 0
        completion = nil
        iterations = []
        startLinkIfNeeded()
        persist()
    }

    func completeIteration(_ scenario: String, iteration: Int) {
        guard active, scenario == self.scenario else { return }
        if let selectedIteration {
            guard iteration == selectedIteration, Self.tracedIterations.contains(iteration) else { return }
            completedIterations = 1
        } else {
            guard iteration == completedIterations, (0..<30).contains(iteration), frames.count > 1 else { return }
            completedIterations += 1
        }
        recordedIteration = iteration
        persist()
        if selectedIteration != nil || completedIterations == 30 {
            active = false
            link?.isPaused = true
            completion = (variant, scenario, completedIterations)
            persist()
        }
    }

    /// The selected iteration's immutable completion evidence, independent of
    /// the asynchronously persisted diagnostic preferences snapshot.
    func finalSamples(iteration: Int) -> [String: Any]? {
        guard selectedIteration == iteration, Self.tracedIterations.contains(iteration), completedIterations == 1,
              recordedIteration == iteration, !frames.isEmpty,
              frames.count <= 4096, frames.allSatisfy({ $0.isFinite && $0 > 0 }),
              iterations.count == frames.count, iterations.allSatisfy({ $0 == iteration }),
              !revision.isEmpty, !variant.isEmpty, !scenario.isEmpty,
              completion?.count == 1 else { return nil }
        var payload = samplePayload()
        payload["session"] = 1
        payload["iteration"] = iteration
        payload["pid"] = Int(ProcessInfo.processInfo.processIdentifier)
        return payload
    }

    private func startLinkIfNeeded() {
        if link == nil {
            link = CADisplayLink(target: DisplayLinkTarget(recorder: self), selector: #selector(DisplayLinkTarget.tick(_:)))
            link?.add(to: .main, forMode: .common)
        }
        link?.isPaused = !active
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard active, !revision.isEmpty, !variant.isEmpty, !scenario.isEmpty else { return }
        // This is the display-link target interval, not a CPU frame duration.
        frames.append(max(0, link.targetTimestamp - link.timestamp) * 1000)
        iterations.append(selectedIteration ?? completedIterations)
        if frames.count > 4096 {
            frames.removeFirst()
            iterations.removeFirst()
        }
        if frames.count.isMultiple(of: 60) {
            persist()
        }
    }

    private func persist() {
        // Defaults are diagnostic only. Asynchronous cfprefsd persistence is
        // never the final sample or completion channel.
        let payload = samplePayload()
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return
        }
        UserDefaults.standard.set(data, forKey: framesKey)
    }

    private func samplePayload() -> [String: Any] {
        [
            "schema": 1,
            "sourceRevision": revision,
            "variant": variant,
            "scenario": scenario,
            "iterationByFrame": iterations,
            "frameIntervalMs": frames,
            "completedIterations": completedIterations,
            "recordedIteration": recordedIteration,
        ]
    }
}

@MainActor
private final class DisplayLinkTarget {
    private weak var recorder: BenchmarkDisplayRecorder?

    init(recorder: BenchmarkDisplayRecorder) {
        self.recorder = recorder
    }

    @objc func tick(_ link: CADisplayLink) {
        recorder?.tick(link)
    }
}
