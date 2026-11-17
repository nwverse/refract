package com.example.refract.search

import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import refract.generated.SearchResultItem
import refract.generated.SearchResultsModel

/** Application-owned request boundary. Completions are delivered serially on the UI thread after start returns. */
internal fun interface SearchPageTransport {
    fun start(
        query: String,
        page: Int,
        generation: Int,
        completion: (SearchPageResult) -> Unit,
    ): () -> Unit
}

internal data class SearchPageResult(
    val query: String,
    val page: Int,
    val generation: Int,
    val items: List<SearchResultItem> = emptyList(),
    val hasMore: Boolean = false,
    val failure: String? = null,
)

/**
 * Native reference implementation for the generated model interface; Refract does not generate this state machine.
 * Page zero replaces the snapshot. Later pages append in response order and update duplicate ids in place.
 */
internal class IncrementalSearchResultsModel(
    private val transport: SearchPageTransport,
) : SearchResultsModel {
    private data class ActiveRequest(
        val query: String,
        val page: Int,
        val generation: Int,
        var cancel: (() -> Unit)? = null,
    )

    private val mutableSearchText = mutableStateOf("")
    private val mutableItems = mutableStateOf<List<SearchResultItem>>(emptyList())
    private val mutableIsLoading = mutableStateOf(false)
    private val mutableHasError = mutableStateOf(false)
    // A settled-empty indicator, not a transient raw-item-count read: existing rows stay in the list during requests.
    private val mutableIsEmpty = mutableStateOf(false)

    override val searchText: State<String> get() = mutableSearchText
    override val items: State<List<SearchResultItem>> get() = mutableItems
    override val isLoading: State<Boolean> get() = mutableIsLoading
    override val hasError: State<Boolean> get() = mutableHasError
    override val isEmpty: State<Boolean> get() = mutableIsEmpty

    private val rowsById = linkedMapOf<String, SearchResultItem>()
    private var active: ActiveRequest? = null
    private var generation = 0
    private var nextPage = 0
    private var hasMore = true
    private var closed = false

    init {
        requestNextPage()
    }

    override fun setSearchText(value: String) {
        if (closed || value == searchText.value) return
        beginGeneration(value, clearRows = true)
    }

    override fun loadNextPage() {
        if (closed || active != null || !hasMore) return
        requestNextPage()
    }

    override fun retry() {
        if (closed || active != null || !hasError.value) return
        requestNextPage()
    }

    /** Refresh retains visible rows until page zero succeeds; a failure leaves them available for retry. */
    fun refresh() {
        if (closed) return
        beginGeneration(searchText.value, clearRows = false)
    }

    /** The native owner calls close when the model leaves its lifecycle. */
    fun close() {
        if (closed) return
        closed = true
        generation += 1
        cancelActiveRequest()
    }

    private fun beginGeneration(query: String, clearRows: Boolean) {
        generation += 1
        cancelActiveRequest()
        mutableSearchText.value = query
        mutableIsLoading.value = true
        mutableHasError.value = false
        updateEmptyState()
        nextPage = 0
        hasMore = true
        if (clearRows) {
            rowsById.clear()
            publishRows()
        }
        requestNextPage()
    }

    private fun requestNextPage() {
        val request = ActiveRequest(searchText.value, nextPage, generation)
        active = request
        mutableIsLoading.value = true
        mutableHasError.value = false
        updateEmptyState()
        request.cancel = transport.start(request.query, request.page, request.generation) { response ->
            accept(request, response)
        }
    }

    private fun accept(request: ActiveRequest, response: SearchPageResult) {
        // A completion belongs to one active request. Duplicate, cancelled, stale and skipped pages change nothing.
        if (active !== request || response.generation != generation ||
            response.query != request.query || response.page != request.page || response.page != nextPage) return
        active = null
        mutableIsLoading.value = false
        if (response.failure != null) {
            mutableHasError.value = true
            updateEmptyState()
            return
        }
        if (response.page == 0) rowsById.clear()
        for (item in response.items) {
            // LinkedHashMap replacement retains the original row position and never emits a duplicate lazy key.
            rowsById[item.id] = item
        }
        publishRows()
        nextPage += 1
        hasMore = response.hasMore
        mutableHasError.value = false
    }

    private fun cancelActiveRequest() {
        val request = active ?: return
        active = null
        request.cancel?.invoke()
        request.cancel = null
    }

    private fun publishRows() {
        mutableItems.value = rowsById.values.toList()
        updateEmptyState()
    }

    private fun updateEmptyState() {
        mutableIsEmpty.value = rowsById.isEmpty() && !isLoading.value && !hasError.value
    }
}
