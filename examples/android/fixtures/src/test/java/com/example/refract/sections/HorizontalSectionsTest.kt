@file:OptIn(ExperimentalTestApi::class)

package com.example.refract.sections

import androidx.activity.ComponentActivity
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.AndroidComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.v2.runAndroidComposeUiTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import refract.generated.GalleryItem
import refract.generated.GalleryModel
import refract.generated.GalleryScreen
import refract.generated.GallerySection

/** Real generated Compose on Native JVM, not an emulator/device or performance benchmark. */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HorizontalSectionsTest {
    @Test
    fun innerHorizontalScrollUsesNativeStateWithoutAnotherVerticalOwner() = runSectionTest {
        val model = FakeGalleryModel()
        setContent { GalleryScreen(model = model) }
        onNodeWithTag("refract_horizontal_sections").assertIsDisplayed()
        onNodeWithText("Alpha section").assertIsDisplayed()
        onNodeWithText("Alpha item 1").assertIsDisplayed()
        onNodeWithText("Beta section").assertIsDisplayed()
        onNodeWithTag("refract_horizontal_section_alpha").performScrollToIndex(4)
        onNodeWithText("Alpha item 5").assertIsDisplayed()
        assertEquals(1500f, horizontalPosition("alpha"), 0f)
    }

    @Test
    fun stableIdsKeepIndependentScrollStateWhenSectionsReorder() = runSectionTest {
        val model = FakeGalleryModel()
        setContent { GalleryScreen(model = model) }
        onNodeWithTag("refract_horizontal_section_alpha").performScrollToIndex(4)
        onNodeWithTag("refract_horizontal_section_beta").performScrollToIndex(1)
        assertEquals(1500f, horizontalPosition("alpha"), 0f)
        assertEquals(500f, horizontalPosition("beta"), 0f)

        runOnIdle { model.swapSections() }

        assertEquals("alpha keeps its own keyed state after moving", 1500f, horizontalPosition("alpha"), 0f)
        assertEquals("beta keeps its own keyed state after moving", 500f, horizontalPosition("beta"), 0f)
        assertEquals(listOf("beta", "alpha"), model.sections.value.map { it.id })
    }

    @Test
    fun sameIdItemShrinkClampsOnlyThatSectionsScrollPosition() = runSectionTest {
        val model = FakeGalleryModel()
        setContent { GalleryScreen(model = model) }
        onNodeWithTag("refract_horizontal_section_alpha").performScrollToIndex(4)
        onNodeWithTag("refract_horizontal_section_beta").performScrollToIndex(1)

        runOnIdle { model.shrinkAlphaItems(to = 2) }

        assertTrue(horizontalPosition("alpha") in 0f..500f)
        assertEquals("beta state is not borrowed or reset", 500f, horizontalPosition("beta"), 0f)
        assertEquals(listOf("Alpha-1", "Alpha-2"), model.sections.value.first().items.map { it.id })
    }

    @Test
    fun samePositionReplacementWithNewIdStartsAtTheBeginning() = runSectionTest {
        val model = FakeGalleryModel()
        setContent { GalleryScreen(model = model) }
        onNodeWithTag("refract_horizontal_section_alpha").performScrollToIndex(4)
        assertEquals(1500f, horizontalPosition("alpha"), 0f)

        runOnIdle { model.replaceSections() }

        assertEquals(0f, horizontalPosition("gamma"), 0f)
        onNodeWithText("Gamma section").assertIsDisplayed()
        onNodeWithText("Gamma item 1").assertIsDisplayed()
        onNodeWithText("Alpha section").assertDoesNotExist()
        onNodeWithText("Alpha item 1").assertDoesNotExist()
    }

    @Test
    fun recreatedCompositionRetainsAppOwnedModelAndSectionIdentity() = runSectionTest {
        val model = FakeGalleryModel()
        var show by mutableStateOf(true)
        setContent {
            if (show) GalleryScreen(model = model)
        }
        onNodeWithText("Alpha section").assertIsDisplayed()
        onNodeWithText("Alpha item 1").assertIsDisplayed()
        runOnIdle { show = false }
        runOnIdle { show = true }
        onNodeWithText("Alpha section").assertIsDisplayed()
        onNodeWithText("Alpha item 1").assertIsDisplayed()
        assertEquals("alpha", model.sections.value.first().id)
        assertEquals("beta", model.sections.value[1].id)
        assertEquals(5, model.sections.value.first().items.size)
        assertTrue(model.sections.value.first().items.map { it.id }.containsAll(listOf("Alpha-1", "Alpha-5")))
    }

    /**
     * Reads native LazyListState through LazyRow semantics. The toolkit reports an estimated pixel
     * position (500 * firstVisibleItemIndex + firstVisibleItemScrollOffset), not an item index.
     */
    private fun AndroidComposeUiTest<ComponentActivity>.horizontalPosition(id: String): Float {
        val range = onNodeWithTag("refract_horizontal_section_$id").fetchSemanticsNode().config
            .getOrNull(SemanticsProperties.HorizontalScrollAxisRange)
        assertNotNull("generated row must expose native horizontal scroll semantics", range)
        return range!!.value()
    }
}

private class FakeGalleryModel : GalleryModel {
    private val _sections = mutableStateOf(
        listOf(
            GallerySection("alpha", "Alpha section", items("Alpha", 5)),
            GallerySection("beta", "Beta section", items("Beta", 5)),
        )
    )
    override val sections: State<List<GallerySection>> = _sections

    fun replaceSections() {
        _sections.value = listOf(GallerySection("gamma", "Gamma section", items("Gamma", 4)))
    }

    fun swapSections() {
        _sections.value = _sections.value.reversed()
    }

    fun shrinkAlphaItems(to: Int) {
        _sections.value = _sections.value.map { section ->
            if (section.id == "alpha") section.copy(items = section.items.take(to)) else section
        }
    }

    private fun items(prefix: String, count: Int): List<GalleryItem> =
        (1..count).map { GalleryItem(id = "$prefix-$it", title = "$prefix item $it") }
}

private fun runSectionTest(block: AndroidComposeUiTest<ComponentActivity>.() -> Unit) =
    runAndroidComposeUiTest<ComponentActivity>(block = block)
