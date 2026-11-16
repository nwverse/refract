struct TypedLayout: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                Section("settings.general") {
                    Text("settings.profile").padding(4)
                }
            }
            HStack(alignment: .center, spacing: 4) {
                Text(verbatim: "Enabled")
                Spacer()
            }
        }.padding(16)
    }
}
