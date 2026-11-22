struct RemoteImage: RefractNativeView {
    let url: String
    let placeholder: Image
    let failure: Image
    let contentDescription: LocalizedStringKey
    let loader: RemoteImageLoader
    var body: some View { placeholder }
}
struct ToggleItem: Identifiable {
    let id: Int
    let title: String
    let enabled: Bool
}
protocol ToggleModel: RefractModel {
    var rows: [ToggleItem] { get }
    func setEnabled(_ id: Int, value: Bool)
}
struct ShadowScreen: View {
    let model: ToggleModel
    let row: RemoteImageLoader
    var body: some View {
        List(model.rows) { row in
            Toggle("settings.item\(row.id)", isOn: Binding(
                get: { row.enabled },
                set: { value in model.setEnabled(row.id, value: value) }
            ))
        }
    }
}
