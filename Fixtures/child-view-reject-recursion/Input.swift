struct First: View {
    var body: some View { Second() }
}

struct Second: View {
    var body: some View { First() }
}
