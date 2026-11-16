import SwiftUI

protocol CounterModel: RefractModel {
    var title: String { get }
    var count: Int { get }
    func increment()
}

struct CounterView: View {
    let model: CounterModel

    var body: some View {
        VStack {
            Text(model.title)
            Text("Count: \(model.count)")
            Button("Increment") { model.increment() }
        }
    }
}
