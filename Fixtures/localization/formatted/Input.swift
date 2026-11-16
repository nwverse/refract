struct LocalizedFormatted: View {
    let name: String
    let count: Int
    let ratio: Double

    var body: some View {
        Text("profile.greeting\(name)\(count)\(ratio)")
    }
}
