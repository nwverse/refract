package com.example.refract.projection

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import refract.generated.CatalogCategory
import refract.generated.CatalogItem
import refract.generated.catalogItems

class CatalogProjectionTest {
    private val first = CatalogItem(4, "first", CatalogCategory.book, 10)
    private val second = CatalogItem(2, "second", CatalogCategory.book, 20)
    private val third = CatalogItem(1, "third", CatalogCategory.book, 20)
    private val movie = CatalogItem(3, "movie", CatalogCategory.movie, 30)

    @Test
    fun emptyAndCategoryFilterPreserveOriginalItems() {
        assertTrue(catalogItems(emptyList(), CatalogCategory.all).isEmpty())
        assertEquals(listOf(movie), catalogItems(listOf(first, movie), CatalogCategory.movie))
        assertSame(movie, catalogItems(listOf(first, movie), CatalogCategory.movie).single())
    }

    @Test
    fun allResetRestoresEveryItemWithDeterministicOrder() {
        assertEquals(listOf(movie, third, second, first), catalogItems(listOf(first, second, third, movie), CatalogCategory.all))
    }

    @Test
    fun descendingRankUsesAscendingIdTieBreakAndRetainsIdentity() {
        val result = catalogItems(listOf(first, second, third), CatalogCategory.all)
        assertEquals(listOf(1, 2, 4), result.map { it.id })
        assertSame(third, result[0])
        assertSame(second, result[1])
        assertSame(first, result[2])
    }
}
