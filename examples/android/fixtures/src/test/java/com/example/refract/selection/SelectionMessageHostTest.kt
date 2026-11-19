package com.example.refract.selection

import example.selection.RefractSelectionContent
import example.selection.RefractSelectionContext
import example.selection.RefractSelectionLink
import example.selection.RefractSelectionRange
import example.selection.SelectionMessageHost
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Plain Native JVM evidence for native host state; no emulator, URL opener or IME. */
class SelectionMessageHostTest {
    private val destinations = mutableListOf<String>()
    private val contexts = mutableListOf<String>()
    private val edits = mutableListOf<String>()
    private val content = RefractSelectionContent("读 🌸 docs", listOf(
        RefractSelectionLink(RefractSelectionRange(5, 9), "https://example.test/docs"),
    ))

    private fun host() = SelectionMessageHost(content,
        onLink = { destinations.add(it) },
        onUseAsContext = { contexts.add(it.description()) },
        onEditWithAI = { edits.add(it.description()) },
    )

    @Test
    fun emptyUnicodeSnapshotIsExplicitAndMovementDoesNotCallActions() {
        val host = host()
        host.moveSelection(5, 5)
        assertTrue(destinations.isEmpty())
        assertTrue(contexts.isEmpty())
        assertTrue(edits.isEmpty())
        host.useAsContext()
        assertEquals(listOf("5:5:读 🌸 docs"), contexts)
        assertTrue(edits.isEmpty())
    }

    @Test
    fun explicitActionsCaptureCurrentUnicodeRangeIndependently() {
        val host = host()
        host.moveSelection(2, 4)
        host.editWithAI()
        assertEquals(listOf("2:4:读 🌸 docs"), edits)
        host.moveSelection(0, 1)
        host.useAsContext()
        assertEquals(listOf("0:1:读 🌸 docs"), contexts)
        assertEquals(listOf("2:4:读 🌸 docs"), edits)
    }

    @Test
    fun linkActivationOnlyDelegatesLiteralDestination() {
        val host = host()
        host.activateLink(0)
        assertEquals(listOf("https://example.test/docs"), destinations)
        assertTrue(contexts.isEmpty())
        assertTrue(edits.isEmpty())
    }

    @Test(expected = IllegalArgumentException::class)
    fun hostRejectsSplitSurrogateRange() {
        host().moveSelection(3, 4)
    }

    @Test(expected = IllegalArgumentException::class)
    fun hostRejectsBackwardsSelection() {
        host().moveSelection(2, 1)
    }

    private fun RefractSelectionContext.description() = "${range.start}:${range.end}:$text"
}
