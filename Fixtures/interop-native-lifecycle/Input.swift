import SwiftUI

protocol SyntheticLifecycleHost: RefractLifecycleHost {
    func foreground()
    func background()
}

struct LifecycleScreen: View {
    let lifecycle: SyntheticLifecycleHost
    @RefractNativeValue var phase: RefractScenePhase

    var body: some View {
        VStack {
            switch phase {
            case .foreground:
                Text(verbatim: "Synthetic foreground")
            case .background:
                Text(verbatim: "Synthetic background")
            }
        }
        .refractNativeValue(phase.state)
        .refractOnAppear
        .refractOnDisappear
    }
}
