protocol SearchResultsModel: RefractModel {
    var searchText: String { get }
    @refractAsync func setSearchText(_ value: String)
}

struct SearchScreen: View {
    let model: SearchResultsModel
    var body: some View {
        TextField("search.results.placeholder", text: Binding(
            get: { model.searchText },
            set: { value in model.setSearchText(value) }
        ))
    }
}
