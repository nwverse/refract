package com.example.refract.animation

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.test.AndroidComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.v2.runAndroidComposeUiTest
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Real Compose on Robolectric, not an emulator, device or animation timing benchmark. */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NativeSelectionEmphasisTest {
    @Test
    fun generatedCallDrivesStatefulNativeTransitionToItsTarget() = runAnimationTest {
        mainClock.autoAdvance = false
        val observer = RecordingObserver()
        val identity = mutableStateOf("first-selection")
        var emphasized by mutableStateOf(false)
        setObservedContent(observer) {
            refract.generated.SelectionEmphasisScreen(
                model = TestModel(identity),
                emphasized = emphasized,
                onEmphasizedChange = { emphasized = it },
            )
        }
        mainClock.advanceTimeBy(0)
        assertEquals(0f, observer.progress("first-selection"), TOLERANCE)
        onNodeWithContentDescription("first-selection").assertIsDisplayed()

        runOnIdle { emphasized = true }
        awaitFrame()
        mainClock.advanceTimeBy(100)
        val firstProgress = observer.progress("first-selection")
        assertTrue(observer.events.toString(), firstProgress > 0f && firstProgress < 1f)
        assertTrue(observer.latest("first-selection")!!.isRunning)

        mainClock.advanceTimeBy(500)
        assertEquals(1f, observer.progress("first-selection"), TOLERANCE)
        assertTrue(!observer.latest("first-selection")!!.isRunning)
        onNodeWithContentDescription("first-selection").assertIsDisplayed()
    }

    @Test
    fun reversalDuringMotionInterruptsFromCurrentProgress() = runAnimationTest {
        mainClock.autoAdvance = false
        val observer = RecordingObserver()
        var emphasized by mutableStateOf(false)
        setObservedContent(observer) {
            NativeSelectionEmphasis(emphasized = emphasized, identity = "selection")
        }
        runOnIdle { emphasized = true }
        awaitFrame()
        mainClock.advanceTimeBy(100)
        awaitFrame()
        val interruptedProgress = observer.progress("selection")
        assertTrue(observer.events.toString(), interruptedProgress > 0f && interruptedProgress < 1f)
        observer.clearHistory()
        runOnIdle { emphasized = false }
        awaitFrame()
        mainClock.advanceTimeBy(100)
        mainClock.advanceTimeByFrame()
        runOnIdle { }
        assertTrue("states=${observer.events}", observer.events.any { !it.isRunning })
        val stoppedIndex = observer.events.indexOfFirst { !it.isRunning }
        val stoppedProgress = observer.events[stoppedIndex].progress
        assertTrue("states=${observer.events}", stoppedProgress > 0f && stoppedProgress < 1f)
        assertTrue("states=${observer.events}", observer.progress("selection") < stoppedProgress)
        mainClock.advanceTimeBy(500)
        assertEquals(0f, observer.progress("selection"), TOLERANCE)
        assertTrue(!observer.latest("selection")!!.isRunning)
    }

    @Test
    fun identityReplacementDuringMotionCancelsOldIdentityAndStartsNewState() = runAnimationTest {
        mainClock.autoAdvance = false
        val observer = RecordingObserver()
        var identity by mutableStateOf("first-selection")
        var emphasized by mutableStateOf(false)
        setObservedContent(observer) {
            NativeSelectionEmphasis(emphasized = emphasized, identity = identity)
        }
        runOnIdle { emphasized = true }
        awaitFrame()
        mainClock.advanceTimeBy(100)
        assertTrue(observer.progress("first-selection") > 0f)
        assertTrue(observer.progress("first-selection") < 1f)

        runOnIdle { identity = "second-selection" }
        awaitFrame()
        mainClock.advanceTimeBy(100)
        mainClock.advanceTimeByFrame()
        runOnIdle { }
        assertEquals("events=${observer.events}", listOf("first-selection"), observer.disposed)
        onNodeWithContentDescription("first-selection").assertDoesNotExist()
        onNodeWithContentDescription("second-selection").assertIsDisplayed()
        val replacementStates = observer.events.filter { it.identity == "second-selection" }
        assertEquals("events=${observer.events}", 0f, replacementStates.first().progress, TOLERANCE)
        assertTrue("events=${observer.events}", replacementStates.any { it.progress > 0f && it.isRunning })

        mainClock.advanceTimeBy(500)
        assertEquals(1f, observer.progress("second-selection"), TOLERANCE)
        assertTrue(!observer.latest("second-selection")!!.isRunning)
    }

    @Test
    fun reducingMotionDuringMotionInterruptsAndSnapsToTarget() = runAnimationTest {
        mainClock.autoAdvance = false
        val observer = RecordingObserver()
        var emphasized by mutableStateOf(false)
        setObservedContent(observer) {
            NativeSelectionEmphasis(emphasized = emphasized, identity = "selection")
        }
        runOnIdle { emphasized = true }
        awaitFrame()
        mainClock.advanceTimeBy(100)
        assertTrue(observer.progress("selection") > 0f)
        assertTrue(observer.progress("selection") < 1f)

        runOnIdle { motionScale.scaleFactor = 0f }
        awaitFrame()
        mainClock.advanceTimeBy(100)
        mainClock.advanceTimeByFrame()
        runOnIdle { }
        assertEquals("events=${observer.events}", 1f, observer.progress("selection"), TOLERANCE)
        assertFalse(observer.latest("selection")!!.isRunning)
        assertTrue("events=${observer.events}", observer.events.none { it.progress > 0.28f && it.progress < 1f })
    }

    @Test
    fun zeroMotionScaleSnapsBothTargetsWithoutIntermediateProgress() = runAnimationTest {
        motionScale.scaleFactor = 0f
        val observer = RecordingObserver()
        var emphasized by mutableStateOf(false)
        setObservedContent(observer) {
            NativeSelectionEmphasis(emphasized = emphasized, identity = "selection")
        }
        runOnIdle { emphasized = true }
        mainClock.advanceTimeBy(100)
        mainClock.advanceTimeByFrame()
        runOnIdle { }
        assertEquals("events=${observer.events}", 1f, observer.progress("selection"), TOLERANCE)
        assertFalse(observer.latest("selection")!!.isRunning)

        runOnIdle { emphasized = false }
        mainClock.advanceTimeBy(100)
        mainClock.advanceTimeByFrame()
        runOnIdle { }
        assertEquals("events=${observer.events}", 0f, observer.progress("selection"), TOLERANCE)
        assertFalse(observer.latest("selection")!!.isRunning)
        onNodeWithContentDescription("selection").assertIsDisplayed()
        assertTrue("events=${observer.events}", observer.events.all { it.progress == 0f || it.progress == 1f })
    }

    @Test
    fun leavingCompositionCancelsRunningAnimationAndDisposesItsIdentity() = runAnimationTest {
        mainClock.autoAdvance = false
        val observer = RecordingObserver()
        var show by mutableStateOf(true)
        var emphasized by mutableStateOf(false)
        setObservedContent(observer) {
            if (show) {
                NativeSelectionEmphasis(emphasized = emphasized, identity = "selection")
            }
        }
        runOnIdle { emphasized = true }
        awaitFrame()
        mainClock.advanceTimeBy(100)
        assertTrue(observer.latest("selection")!!.isRunning)

        runOnIdle { show = false }
        awaitFrame()
        mainClock.advanceTimeBy(100)
        mainClock.advanceTimeByFrame()
        runOnIdle { }
        assertEquals("events=${observer.events}", listOf("selection"), observer.disposed)
        onNodeWithContentDescription("selection").assertDoesNotExist()
    }

    private val motionScale = TestMotionDurationScale(1f)
    private val effectDispatcher = StandardTestDispatcher()

    private fun runAnimationTest(block: AndroidComposeUiTest<ComponentActivity>.() -> Unit) =
        runAndroidComposeUiTest<ComponentActivity>(
            effectContext = effectDispatcher + motionScale,
            block = block,
        )

    private fun AndroidComposeUiTest<ComponentActivity>.setObservedContent(
        observer: RecordingObserver,
        content: @androidx.compose.runtime.Composable () -> Unit,
    ) {
        setContent {
            CompositionLocalProvider(LocalSelectionEmphasisObserver provides observer) {
                content()
            }
        }
    }

    private fun AndroidComposeUiTest<ComponentActivity>.awaitFrame() {
        mainClock.advanceTimeByFrame()
        effectDispatcher.scheduler.runCurrent()
    }

    private class TestMotionDurationScale(override var scaleFactor: Float) : MotionDurationScale

    private class TestModel(override val identity: State<String>) : refract.generated.SelectionEmphasisModel

    private data class EmphasisState(
        val identity: String,
        val progress: Float,
        val isRunning: Boolean,
    )

    private class RecordingObserver : SelectionEmphasisObserver {
        val appeared = mutableListOf<String>()
        val disposed = mutableListOf<String>()
        val events = mutableListOf<EmphasisState>()

        fun latest(identity: String): EmphasisState? = events.lastOrNull { it.identity == identity }

        fun progress(identity: String): Float = latest(identity)!!.progress

        fun clearHistory() {
            events.clear()
        }

        override fun onAppear(identity: String) {
            appeared += identity
        }

        override fun onStateChanged(identity: String, progress: Float, isRunning: Boolean) {
            events += EmphasisState(identity, progress, isRunning)
        }

        override fun onDispose(identity: String) {
            disposed += identity
        }
    }

    private companion object {
        const val TOLERANCE = 0.001f
    }
}
