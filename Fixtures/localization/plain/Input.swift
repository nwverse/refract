struct LocalizedPlain: View {
    var body: some View {
        VStack {
            Text("settings.title")
            Text(LocalizedStringKey("settings.subtitle"))
            Text(String(localized: "settings.footer"))
            Text(verbatim: "Debug: $value")
        }
    }
}
