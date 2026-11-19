import SwiftUI

@main
@MainActor
struct RefractBenchApp: App {
    @StateObject private var model = BenchmarkSettingsModel()
    @Environment(\.scenePhase) private var scenePhase

    private var variant: String {
        ProcessInfo.processInfo.environment["REFRACT_BENCH_VARIANT"] ?? "generated"
    }

    private var scenario: String {
        ProcessInfo.processInfo.environment["REFRACT_BENCH_SCENARIO"] ?? "idle"
    }

    init() {
        BenchmarkDisplayRecorder.shared.prepareForLaunch()
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
                if let completion = BenchmarkDisplayRecorder.shared.completion {
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
private func runScroll(variant: String, model: BenchmarkSettingsModel) async {
    BenchmarkDisplayRecorder.shared.beginScenario("scroll")
    let destinations = (1...30).map { min($0 * 20, 199) }
    for (iteration, destination) in destinations.enumerated() {
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.linear(duration: 0.75)) {
            NotificationCenter.default.post(name: .refractBenchmarkScroll, object: destination)
        }
        try? await Task.sleep(for: .milliseconds(1200))
        BenchmarkDisplayRecorder.shared.completeIteration("scroll", iteration: iteration)
    }
}

@MainActor
private func runUpdates(variant: String, model: BenchmarkSettingsModel) async {
    BenchmarkDisplayRecorder.shared.beginScenario("stateUpdate")
    try? await Task.sleep(for: .milliseconds(500))
    for iteration in 0..<30 {
        for _ in 0..<8 {
            model.setEnabled(0, value: !model.rows[0].enabled)
            try? await Task.sleep(for: .milliseconds(250))
        }
        BenchmarkDisplayRecorder.shared.completeIteration("stateUpdate", iteration: iteration)
    }
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
