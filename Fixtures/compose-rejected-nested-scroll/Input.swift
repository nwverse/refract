struct InvalidNestedScroll: View {
    var body: some View {
        ScrollView {
            List {
                Text(verbatim: "Row")
            }
        }
    }
}
