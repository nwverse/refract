package com.example.refract.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import refract.generated.SearchResultItem

class IncrementalSearchResultsModelTest {
    @Test
    fun appendUpdatesDuplicateIdsWithoutChangingTheirIdentityOrPosition() {
        val transport = RecordingTransport()
        val model = IncrementalSearchResultsModel(transport)
        transport.complete(0, items = listOf(item("a", "first"), item("b", "second")), hasMore = true)
        model.loadNextPage()
        transport.complete(1, items = listOf(item("b", "updated"), item("c", "third")))

        assertEquals(listOf("a", "b", "c"), model.items.value.map { it.id })
        assertEquals(listOf("first", "updated", "third"), model.items.value.map { it.title })
        assertFalse(model.isLoading.value)
        assertFalse(model.hasError.value)
        assertFalse(model.isEmpty.value)
        transport.complete(1, items = listOf(item("c", "duplicate completion")), hasMore = true)
        assertEquals(listOf("first", "updated", "third"), model.items.value.map { it.title })
        assertEquals(2, transport.requests.size)
    }

    @Test
    fun replacementRetainsLogicalIdsAndRemovesMissingRows() {
        val transport = RecordingTransport()
        val model = IncrementalSearchResultsModel(transport)
        transport.complete(0, items = listOf(item("a", "old a"), item("b", "old b")))
        model.refresh()
        assertEquals(listOf("a", "b"), model.items.value.map { it.id })
        transport.complete(1, items = listOf(item("b", "new b"), item("c", "new c")))

        assertEquals(listOf("b", "c"), model.items.value.map { it.id })
        assertEquals(listOf("new b", "new c"), model.items.value.map { it.title })
        assertEquals(1, transport.requests[1].generation)
    }

    @Test
    fun staleAndDuplicateResponsesAfterSearchCancellationAreRejected() {
        val transport = RecordingTransport()
        val model = IncrementalSearchResultsModel(transport)
        transport.complete(0, items = listOf(item("old", "old")), hasMore = true)
        model.loadNextPage()
        val oldAppend = transport.requests[1]
        model.setSearchText("new query")
        val replacement = transport.requests[2]

        assertEquals(1, transport.requests[1].cancellationCount)
        oldAppend.succeed(items = listOf(item("stale", "stale")))
        replacement.succeed(items = listOf(item("new", "new")), hasMore = true)
        replacement.succeed(items = listOf(item("duplicate", "duplicate")))
        assertEquals(listOf("new"), model.items.value.map { it.id })
        assertEquals("new query", model.searchText.value)
        assertEquals(3, transport.requests.size)
    }

    @Test
    fun outOfOrderPageCannotConsumeTheExpectedRequest() {
        val transport = RecordingTransport()
        val model = IncrementalSearchResultsModel(transport)
        val request = transport.requests[0]
        request.succeed(page = 1, items = listOf(item("skipped", "skipped")))
        assertTrue(model.isLoading.value)
        assertTrue(model.items.value.isEmpty())

        request.succeed(page = 0, items = listOf(item("expected", "expected")))
        assertFalse(model.isLoading.value)
        assertEquals(listOf("expected"), model.items.value.map { it.id })
    }

    @Test
    fun errorRetryReusesOnlyTheFailedNextPage() {
        val transport = RecordingTransport()
        val model = IncrementalSearchResultsModel(transport)
        transport.complete(0, items = listOf(item("a", "retained")), hasMore = true)
        model.loadNextPage()
        transport.fail(1, "unavailable")
        assertTrue(model.hasError.value)
        assertEquals(listOf("a"), model.items.value.map { it.id })
        assertEquals(2, transport.requests.size)

        model.retry()
        assertEquals(1, transport.requests[2].page)
        assertEquals(0, transport.requests[2].generation)
        transport.complete(2, items = listOf(item("b", "appended")))
        assertEquals(listOf("a", "b"), model.items.value.map { it.id })
        assertFalse(model.hasError.value)
    }

    @Test
    fun emptyAndInFlightStatesDoNotStartDuplicateRequests() {
        val transport = RecordingTransport()
        val model = IncrementalSearchResultsModel(transport)
        assertTrue(model.isLoading.value)
        assertFalse(model.isEmpty.value)
        model.retry()
        assertEquals(1, transport.requests.size)
        transport.complete(0, items = emptyList(), hasMore = true)
        assertTrue(model.isEmpty.value)
        model.loadNextPage()
        assertEquals(2, transport.requests.size)
        model.close()
        assertEquals(1, transport.requests[1].cancellationCount)
        transport.requests[1].succeed(items = listOf(item("late", "late")))
        assertTrue(model.items.value.isEmpty())
    }

    private fun item(id: String, title: String) = SearchResultItem(id = id, title = title)

    private class Request(
        val query: String,
        val page: Int,
        val generation: Int,
        private val completion: (SearchPageResult) -> Unit,
    ) {
        var cancellationCount = 0
            private set

        fun cancel() {
            cancellationCount += 1
        }

        fun succeed(
            query: String = this.query,
            page: Int = this.page,
            generation: Int = this.generation,
            items: List<SearchResultItem>,
            hasMore: Boolean = false,
        ) {
            completion(SearchPageResult(query, page, generation, items, hasMore))
        }

        fun fail(message: String) {
            completion(SearchPageResult(query, page, generation, failure = message))
        }
    }

    private class RecordingTransport : SearchPageTransport {
        val requests = mutableListOf<Request>()

        override fun start(
            query: String,
            page: Int,
            generation: Int,
            completion: (SearchPageResult) -> Unit,
        ): () -> Unit {
            val request = Request(query, page, generation, completion)
            requests += request
            return request::cancel
        }

        fun complete(index: Int, items: List<SearchResultItem>, hasMore: Boolean = false) {
            requests[index].succeed(items = items, hasMore = hasMore)
        }

        fun fail(index: Int, message: String) {
            requests[index].fail(message)
        }
    }
}
