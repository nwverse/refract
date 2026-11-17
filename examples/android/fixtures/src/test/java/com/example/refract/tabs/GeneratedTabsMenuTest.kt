package com.example.refract.tabs

import androidx.activity.ComponentActivity
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import refract.generated.HomeTab
import refract.generated.HomeTabsScreen
import refract.generated.OverviewModel

/**
 * Native JVM (Robolectric) verification of the actual CLI-generated typed tab + overflow menu screen.
 *
 * These tests run the generated `HomeTabsScreen` verbatim, with the host owning the selected tab exactly as a
 * hand-written controlled component would. They are not emulator or device results and make no visual-parity or
 * performance claim. No hand-written replacement for the generated screen participates in these tests.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class GeneratedTabsMenuTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private lateinit var model: RecordingOverviewModel
    private var selectedTab by mutableStateOf(HomeTab.overview)

    @Test
    fun selectedTabDrivesNativeSelectedStateAndDestination() {
        renderGeneratedScreen()

        compose.onNodeWithText("Overview body").assertIsDisplayed()
        compose.onNodeWithText("Overview").assertIsSelected()
        compose.onNodeWithText("Activity").assertIsNotSelected()
        compose.onNodeWithText("Activity body").assertDoesNotExist()
    }

    @Test
    fun tabClickReachesTheHostCallbackAndSelectsTheTypedDestination() {
        renderGeneratedScreen()

        compose.onNodeWithText("Activity").performClick()
        compose.waitForIdle()

        assertEquals(HomeTab.activity, selectedTab)
        compose.onNodeWithText("Activity").assertIsSelected()
        compose.onNodeWithText("Overview").assertIsNotSelected()
        compose.onNodeWithText("Activity body").assertIsDisplayed()
        compose.onNodeWithText("Overview body").assertDoesNotExist()

        compose.onNodeWithText("Overview").performClick()
        compose.waitForIdle()
        assertEquals(HomeTab.overview, selectedTab)
        compose.onNodeWithText("Overview body").assertIsDisplayed()
    }

    @Test
    fun hostDrivenSelectionChangeUpdatesTheGeneratedScreen() {
        renderGeneratedScreen()

        compose.activity.runOnUiThread { selectedTab = HomeTab.activity }
        compose.waitForIdle()

        compose.onNodeWithText("Activity").assertIsSelected()
        compose.onNodeWithText("Activity body").assertIsDisplayed()
    }

    @Test
    fun overflowMenuActionsCallTypedModelMethods() {
        renderGeneratedScreen()

        // The overflow affordance carries the generated localized content description.
        compose.onNodeWithContentDescription("More actions").assertIsDisplayed().performClick()
        compose.waitForIdle()

        compose.onNodeWithText("Refresh").assertIsDisplayed().performClick()
        compose.waitForIdle()
        assertEquals(1, model.refreshCount)
        assertEquals(0, model.resetCount)

        compose.onNodeWithContentDescription("More actions").performClick()
        compose.waitForIdle()
        compose.onNodeWithText("Reset").assertIsDisplayed().performClick()
        compose.waitForIdle()
        assertEquals(1, model.resetCount)
        assertTrue(model.calls == listOf("refresh", "reset"))
    }

    private fun renderGeneratedScreen() {
        model = RecordingOverviewModel()
        selectedTab = HomeTab.overview
        compose.setContent {
            // The native host owns the selected tab, exactly as in the documented host contract.
            HomeTabsScreen(
                model = model,
                tab = selectedTab,
                onTabChange = { selectedTab = it },
            )
        }
        compose.waitForIdle()
    }
}

private class RecordingOverviewModel : OverviewModel {
    private val titleState = mutableStateOf("Overview title")
    var refreshCount = 0
        private set
    var resetCount = 0
        private set
    val calls = mutableListOf<String>()

    override val title: State<String>
        get() = titleState

    override fun refresh() {
        refreshCount += 1
        calls += "refresh"
    }

    override fun reset() {
        resetCount += 1
        calls += "reset"
    }
}
