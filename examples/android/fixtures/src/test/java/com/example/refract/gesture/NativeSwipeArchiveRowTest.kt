package com.example.refract.gesture

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.test.AndroidComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.v2.runAndroidComposeUiTest
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.runtime.CompositionLocalProvider
import kotlinx.coroutines.test.StandardTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import refract.generated.ArchiveItem
import refract.generated.ArchiveListModel
import refract.generated.ArchiveListScreen

/** Real generated Compose and native gestures on Robolectric, not a device or timing benchmark. */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NativeSwipeArchiveRowTest {
    @Test
    fun shortSwipeRevealsActionWithoutArchivingAndMenuCancelSharesConfirmation() = runSwipeTest {
        val model = FakeArchiveModel()
        setContent { ArchiveListScreen(model = model) }
        onNodeWithText("First synthetic item").assertIsDisplayed()
        onNodeWithTag("swipe_archive_row").performTouchInput { swipeLeft(endX = centerX - width / 4) }
        onNodeWithText("Archive this item?").assertIsDisplayed()
        assertEquals(listOf("request:first"), model.calls)
        onNodeWithText("Cancel").performClick()
        onNodeWithText("Archive this item?").assertDoesNotExist()
        assertEquals(listOf("request:first", "cancel"), model.calls)
    }

    @Test
    fun revealedActionAndAccessibleMenuConfirmThroughTheSameModelAction() = runSwipeTest {
        val model = FakeArchiveModel()
        setContent { ArchiveListScreen(model = model) }
        onNodeWithTag("swipe_archive_row").performTouchInput { swipeLeft() }
        onNodeWithText("Archive this item?").assertIsDisplayed()
        onNodeWithText("Archive item").performClick()
        onNodeWithText("Archive this item?").assertDoesNotExist()
        assertEquals(listOf("request:first", "archive:first"), model.calls)

        onNodeWithContentDescription("Row actions").performClick()
        onNodeWithText("Archive").performClick()
        onNodeWithText("Archive item").performClick()
        assertEquals(listOf("request:first", "archive:first", "request:first", "archive:first"), model.calls)
    }

    @Test
    fun accessibilityCustomActionUsesTheSamePendingConfirmation() = runSwipeTest {
        val model = FakeArchiveModel()
        setContent { ArchiveListScreen(model = model) }
        val actions = onNodeWithTag("swipe_archive_row").fetchSemanticsNode().config
            .getOrNull(SemanticsActions.CustomActions).orEmpty()
        val archive = actions.first { it.label == "Archive" }
        archive.action()
        onNodeWithText("Archive this item?").assertIsDisplayed()
        assertEquals(listOf("request:first"), model.calls)
        onNodeWithText("Archive item").performClick()
        assertEquals(listOf("request:first", "archive:first"), model.calls)
    }

    @Test
    fun pendingRequestIsIdempotentAndCancelAllowsNewRequest() = runSwipeTest {
        val model = FakeArchiveModel()
        setContent { ArchiveListScreen(model = model) }
        onNodeWithContentDescription("Row actions").performClick()
        onNodeWithText("Archive").performClick()
        onNodeWithTag("swipe_revealed_archive").performClick()
        assertEquals(listOf("request:first"), model.calls)
        onNodeWithText("Cancel").performClick()
        onNodeWithContentDescription("Row actions").performClick()
        onNodeWithText("Archive").performClick()
        onNodeWithText("Archive item").performClick()
        assertEquals(listOf("request:first", "cancel", "request:first", "archive:first"), model.calls)
    }

    @Test
    fun identityReplacementDropsTheOldPendingConfirmation() = runSwipeTest {
        val model = FakeArchiveModel()
        var identity by mutableStateOf("first")
        setContent {
            NativeSwipeArchiveRow(
                identifier = identity,
                title = "Synthetic item",
                onRequest = model::requestArchive,
                onConfirm = model::archive,
                onCancel = model::cancelArchive,
            )
        }
        onNodeWithContentDescription("Row actions").performClick()
        onNodeWithText("Archive").performClick()
        onNodeWithText("Archive this item?").assertIsDisplayed()
        runOnIdle { identity = "second" }
        onNodeWithText("Archive this item?").assertDoesNotExist()
        assertEquals(listOf("request:first"), model.calls)
    }

    @Test
    fun leavingCompositionDropsPendingWithoutArchiving() = runSwipeTest {
        val model = FakeArchiveModel()
        var show by mutableStateOf(true)
        setContent {
            if (show) {
                ArchiveListScreen(model = model)
            }
        }
        onNodeWithContentDescription("Row actions").performClick()
        onNodeWithText("Archive").performClick()
        onNodeWithText("Archive this item?").assertIsDisplayed()
        runOnIdle { show = false }
        onNodeWithText("Archive this item?").assertDoesNotExist()
        assertEquals(listOf("request:first"), model.calls)
    }

    @Test
    fun zeroMotionSettlesRevealedAndCancelledRowsImmediately() = runSwipeTest {
        motionScale.scaleFactor = 0f
        val model = FakeArchiveModel()
        val settlements = mutableListOf<Pair<SwipeToDismissBoxValue, Boolean>>()
        val observer = object : SwipeArchiveObserver {
            val progress = mutableListOf<String>()
            override fun onSettle(identifier: String, target: SwipeToDismissBoxValue, animated: Boolean) {
                settlements += target to animated
            }
            override fun onProgress(identifier: String, current: SwipeToDismissBoxValue, target: SwipeToDismissBoxValue, progress: Float) {
                this.progress += "$current/$target/$progress"
            }
        }
        setContent {
            CompositionLocalProvider(LocalSwipeArchiveObserver provides observer) {
                ArchiveListScreen(model = model)
            }
        }
        onNodeWithTag("swipe_archive_row").performTouchInput { swipeLeft() }
        onNodeWithTag("swipe_revealed_archive").performClick()
        onNodeWithText("Cancel").performClick()
        waitForIdle()
        assertEquals(listOf("request:first", "cancel"), model.calls)
        val reducedMotionSettlements = settlements.filterNot { it.second }
        assertTrue(settlements.toString(), reducedMotionSettlements.isNotEmpty())
        assertEquals(SwipeToDismissBoxValue.Settled, reducedMotionSettlements.last().first)
        assertTrue(settlements.toString(), settlements.indexOf(reducedMotionSettlements.last()) == settlements.lastIndex)
    }

    private val motionScale = TestMotionDurationScale(1f)

    private fun runSwipeTest(block: AndroidComposeUiTest<ComponentActivity>.() -> Unit) =
        runAndroidComposeUiTest<ComponentActivity>(
            effectContext = StandardTestDispatcher() + motionScale,
            block = block,
        )

    private class TestMotionDurationScale(override var scaleFactor: Float) : MotionDurationScale
}

private class FakeArchiveModel : ArchiveListModel {
    override val items = mutableStateOf(listOf(ArchiveItem(id = "first", title = "First synthetic item")))
    val calls = mutableListOf<String>()

    override fun requestArchive(identifier: String) {
        calls += "request:$identifier"
    }

    override fun archive(identifier: String) {
        calls += "archive:$identifier"
    }

    override fun cancelArchive() {
        calls += "cancel"
    }
}
