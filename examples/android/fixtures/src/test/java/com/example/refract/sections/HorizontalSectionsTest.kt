@file:OptIn(ExperimentalTestApi::class)

package com.example.refract.sections

import androidx.activity.ComponentActivity
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.AndroidComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.v2.runAndroidComposeUiTest
import org.junit.Assert.assertEquals
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
    }

    @Test
    fun sectionReplacementPreservesIdentityAndKeepsIndependentHorizontalState() = runSectionTest {
        val model = FakeGalleryModel()
        setContent { GalleryScreen(model = model) }
        onNodeWithTag("refract_horizontal_section_alpha").performScrollToIndex(2)
        onNodeWithText("Alpha item 3").assertIsDisplayed()
        model.replaceSections()
        onNodeWithText("Gamma section").assertIsDisplayed()
        onNodeWithText("Gamma item 1").assertIsDisplayed()
        onNodeWithText("Alpha section").assertDoesNotExist()
        onNodeWithText("Alpha item 1").assertDoesNotExist()
        onNodeWithTag("refract_horizontal_section_gamma").assertIsDisplayed()
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
}

private class FakeGalleryModel : GalleryModel {
    private val _sections = mutableStateOf(
        listOf(
            GallerySection("alpha", "Alpha section", items("Alpha", 5)),
            GallerySection("beta", "Beta section", items("Beta", 2)),
        )
    )
    override val sections: State<List<GallerySection>> = _sections

    fun replaceSections() {
        _sections.value = listOf(GallerySection("gamma", "Gamma section", items("Gamma", 4)))
    }

    private fun items(prefix: String, count: Int): List<GalleryItem> =
        (1..count).map { GalleryItem(id = "$prefix-$it", title = "$prefix item $it") }
}

private fun runSectionTest(block: AndroidComposeUiTest<ComponentActivity>.() -> Unit) =
    runAndroidComposeUiTest<ComponentActivity>(block = block)
