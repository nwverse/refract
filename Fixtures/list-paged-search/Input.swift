import SwiftUI

struct SearchResultItem: Identifiable {
    let id: String
    let title: String
}

protocol SearchResultsModel: RefractModel {
    var searchText: String { get }
    var items: [SearchResultItem] { get }
    var isLoading: Bool { get }
    var hasError: Bool { get }
    var isEmpty: Bool { get }
    func setSearchText(_ value: String)
    func loadNextPage()
    func retry()
}

struct PagedSearchScreen: View {
    let model: SearchResultsModel

    var body: some View {
        VStack {
            TextField("search.results.placeholder", text: Binding(
                get: { model.searchText },
                set: { value in model.setSearchText(value) }
            ))
            if model.isLoading {
                Text(verbatim: "Loading")
            }
            if model.hasError {
                Text(verbatim: "Could not load results")
                Button { model.retry() } label: {
                    Text(verbatim: "Retry")
                }
            }
            if model.isEmpty {
                Text(verbatim: "No results")
            } else {
                List(model.items) { result in
                    Text(result.title)
                }
            }
            Button { model.loadNextPage() } label: {
                Text(verbatim: "Load more")
            }
        }
    }
}
