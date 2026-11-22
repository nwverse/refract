import SwiftUI

@main
@MainActor
struct RefractBenchApp: App {
    @StateObject private var model = BenchmarkSettingsModel()
    @StateObject private var recorder = BenchmarkDisplayRecorder.shared
    @StateObject private var traceReadiness: TraceReadiness
    @Environment(\.scenePhase) private var scenePhase
    @State private var traceIdentityError = ""

    private var selectedIteration: Int? {
        guard let value = ProcessInfo.processInfo.environment["REFRACT_BENCH_ITERATION"] else { return nil }
        return Int(value)
    }

    private var variant: String {
        ProcessInfo.processInfo.environment["REFRACT_BENCH_VARIANT"] ?? "generated"
    }

    private var scenario: String {
        ProcessInfo.processInfo.environment["REFRACT_BENCH_SCENARIO"] ?? "idle"
    }

    private var revision: String {
        ProcessInfo.processInfo.environment["REFRACT_BENCH_REVISION"] ?? ""
    }

    init() {
        BenchmarkDisplayRecorder.shared.prepareForLaunch()
        _traceReadiness = StateObject(wrappedValue: TraceReadiness())
    }

    @MainActor
    private func beginTrace() {
        guard let iteration = selectedIteration, let directory = traceControlDirectory() else {
            traceIdentityError = "The selected iteration has no control directory"
            return
        }
        do {
            try publishTracePacket(named: "begin.json", in: directory,
                                   revision: revision, variant: variant, scenario: scenario,
                                   iteration: iteration, state: "begin")
            recorder.beginSelectedIteration = true
            Task { await runTracedIteration(variant: variant, model: model) }
        } catch {
            traceIdentityError = "Native Begin identity failed: \(error.localizedDescription)"
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch (variant, scenario) {
                case ("generated", "scroll"), ("reference", "scroll"),
                     ("generated", "stateUpdate"), ("reference", "stateUpdate"),
                     ("generated", "startup"), ("reference", "startup"):
                    Group {
                        if variant == "generated" {
                            GeneratedSettingsScreen(model: model)
                        } else {
                            ReferenceSettingsScreen(model: model)
                        }
                    }
                default:
                    Text("Unsupported benchmark selection")
                }
            }
            .overlay(alignment: .bottom) {
                if selectedIteration != nil {
                    Text(traceIdentityError)
                        .accessibilityIdentifier("refract_benchmark_trace_identity_error")
                    if !recorder.beginSelectedIteration {
                        Button("BeginIteration", action: beginTrace)
                        .disabled(!traceReadiness.isReady)
                        .accessibilityIdentifier("refract_benchmark_begin_iteration")
                        Text("\(variant) \(scenario) \(traceReadiness.isReady ? "ready" : "waiting")")
                            .accessibilityIdentifier("refract_benchmark_iteration_ready")
                    }
                }
                if let completion = recorder.completion {
                    Text("\(completion.variant) \(completion.scenario) complete \(completion.count)")
                        .accessibilityIdentifier("refract_benchmark_complete")
                        .font(.caption2)
                        .foregroundStyle(.clear)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    BenchmarkDisplayRecorder.shared.sceneBecameActive()
                }
            }
            .task {
                guard selectedIteration == nil else { return }
                switch (variant, scenario) {
                case ("generated", "scroll"), ("reference", "scroll"):
                    await runScroll(variant: variant, model: model)
                case ("generated", "stateUpdate"), ("reference", "stateUpdate"):
                    await runUpdates(variant: variant, model: model)
                default:
                    break
                }
            }
        }
    }
}

@MainActor
private final class TraceReadiness: ObservableObject {
    @Published private(set) var isReady = false

    init() {
        guard let iteration = selectedIteration(), (0..<30).contains(iteration),
              let directory = traceControlDirectory(),
              let data = try? JSONSerialization.data(withJSONObject: [
                "schema": 1, "session": 1,
                "revision": ProcessInfo.processInfo.environment["REFRACT_BENCH_REVISION"] ?? "",
                "variant": ProcessInfo.processInfo.environment["REFRACT_BENCH_VARIANT"] ?? "",
                "scenario": ProcessInfo.processInfo.environment["REFRACT_BENCH_SCENARIO"] ?? "",
                "iteration": iteration, "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "process": "running", "state": "ready",
              ], options: [.sortedKeys]) else { return }
        do {
            try data.write(to: directory.appendingPathComponent("native-process.json"), options: .withoutOverwriting)
            Task { [weak self] in
                guard let self else { return }
                while !recorderReady(in: directory) {
                    try await Task.sleep(for: .milliseconds(10))
                }
                self.isReady = true
            }
        } catch {
            // XCTest fails closed when the native identity packet is missing.
        }
    }
}

@MainActor
private func runTracedIteration(variant: String, model: BenchmarkSettingsModel) async {
    guard let iteration = selectedIteration(), (0..<30).contains(iteration),
          let directory = traceControlDirectory() else { return }
    let scenario = ProcessInfo.processInfo.environment["REFRACT_BENCH_SCENARIO"] ?? ""
    let revision = ProcessInfo.processInfo.environment["REFRACT_BENCH_REVISION"] ?? ""
    do {
        while !recorderReady(in: directory) {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.yield()
        switch (variant, scenario) {
        case ("generated", "scroll"), ("reference", "scroll"):
            await runScroll(variant: variant, model: model)
        case ("generated", "stateUpdate"), ("reference", "stateUpdate"):
            await runUpdates(variant: variant, model: model)
        default:
            return
        }
        try publishTracePacket(named: "native-completion.json", in: directory,
                               revision: revision, variant: variant, scenario: scenario,
                               iteration: iteration, state: "complete",
                               completion: "\(variant) \(scenario) complete 1")
    } catch {
        // XCTest observes the absence of native completion and fails closed.
    }
}

@MainActor
private func runScroll(variant: String, model: BenchmarkSettingsModel) async {
    BenchmarkDisplayRecorder.shared.beginScenario("scroll")
    if let iteration = selectedIteration() {
        try? await Task.sleep(for: .milliseconds(300))
        await scrollStep(iteration: iteration)
        try? await Task.sleep(for: .milliseconds(1200))
        BenchmarkDisplayRecorder.shared.completeIteration("scroll", iteration: iteration)
        return
    }
    for iteration in 0..<30 {
        try? await Task.sleep(for: .milliseconds(300))
        await scrollStep(iteration: iteration)
        try? await Task.sleep(for: .milliseconds(1200))
        BenchmarkDisplayRecorder.shared.completeIteration("scroll", iteration: iteration)
    }
}

@MainActor
private func scrollStep(iteration: Int) async {
    let destination = min((iteration + 1) * 20, 199)
    withAnimation(.linear(duration: 0.75)) {
        NotificationCenter.default.post(name: .refractBenchmarkScroll, object: destination)
    }
}

@MainActor
private func runUpdates(variant: String, model: BenchmarkSettingsModel) async {
    BenchmarkDisplayRecorder.shared.beginScenario("stateUpdate")
    try? await Task.sleep(for: .milliseconds(500))
    for iteration in iterationRange() {
        for _ in 0..<8 {
            model.setEnabled(0, value: !model.rows[0].enabled)
            try? await Task.sleep(for: .milliseconds(250))
        }
        BenchmarkDisplayRecorder.shared.completeIteration("stateUpdate", iteration: iteration)
    }
}

@MainActor
private func traceControlDirectory() -> URL? {
    ProcessInfo.processInfo.environment["REFRACT_BENCH_TRACE_CONTROL"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }
}

@MainActor
private func publishTracePacket(named name: String, in directory: URL, revision: String,
                                variant: String, scenario: String, iteration: Int,
                                state: String, completion: String? = nil) throws {
    var packet: [String: Any] = [
        "schema": 1,
        "session": 1,
        "revision": revision,
        "variant": variant,
        "scenario": scenario,
        "iteration": iteration,
        "pid": Int(ProcessInfo.processInfo.processIdentifier),
        "process": "running",
        "state": state,
    ]
    if let completion {
        packet["completion"] = completion
    }
    let data = try JSONSerialization.data(withJSONObject: packet, options: [.sortedKeys])
    let destination = directory.appendingPathComponent(name)
    guard !FileManager.default.fileExists(atPath: destination.path) else {
        throw NSError(domain: "RefractBench.TraceIdentity", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Refusing to replace \(name)"])
    }
    try data.write(to: destination, options: .withoutOverwriting)
}

@MainActor
private func recorderReady(in directory: URL) -> Bool {
    guard let iteration = selectedIteration(), let data = try? Data(contentsOf:
            directory.appendingPathComponent("recorder-ready.json")),
          let packet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          packet["schema"] as? Int == 1, packet["session"] as? Int == 1,
          packet["variant"] as? String == ProcessInfo.processInfo.environment["REFRACT_BENCH_VARIANT"],
          packet["scenario"] as? String == ProcessInfo.processInfo.environment["REFRACT_BENCH_SCENARIO"],
          packet["iteration"] as? Int == iteration,
          packet["revision"] as? String == ProcessInfo.processInfo.environment["REFRACT_BENCH_REVISION"],
          let pid = packet["pid"] as? Int32, pid == ProcessInfo.processInfo.processIdentifier else { return false }
    return true
}

@MainActor
private func selectedIteration() -> Int? {
    guard let value = ProcessInfo.processInfo.environment["REFRACT_BENCH_ITERATION"] else { return nil }
    return Int(value)
}

@MainActor
private func iterationRange() -> Range<Int> {
    if let iteration = selectedIteration(), (0..<30).contains(iteration) {
        return iteration..<(iteration + 1)
    }
    return 0..<30
}

extension Notification.Name {
    static let refractBenchmarkScroll = Notification.Name("refract.benchmark.scroll")
}

/// The host owns a single input script. Both screens receive exactly the same
/// native scroll notification; it does not select or translate view content.
struct BenchmarkScrollDriver: ViewModifier {
    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onReceive(NotificationCenter.default.publisher(for: .refractBenchmarkScroll)) { notification in
                    guard let destination = notification.object as? Int else { return }
                    withAnimation(.linear(duration: 0.75)) {
                        proxy.scrollTo(destination, anchor: .top)
                    }
                }
        }
    }
}
