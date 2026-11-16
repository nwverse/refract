struct TypedScroll: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "One")
                Text(verbatim: "Two")
            }
        }
    }
}
