package com.example.refract.animation

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Real Compose on Robolectric, not an emulator, device or timing benchmark. */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NativeSaveConfirmationTest {
    @Test
    fun generatedCallRunsNativeTransitionAndReachesItsTarget() = runAnimationTest {
        val observer = RecordingObserver()
        val saved = mutableStateOf(false)
        setContent {
            CompositionLocalProvider(LocalSaveConfirmationObserver provides observer) {
                refract.generated.SaveConfirmationScreen(
                    saved = saved.value,
                    onSavedChange = { saved.value = it },
                )
            }
        }
        onNodeWithContentDescription("profile-save").assertDoesNotExist()

        runOnIdle { saved.value = true }
        onNodeWithContentDescription("profile-save").assertIsDisplayed()
        assertEquals(observer.states.toString(), TransitionState(visible = true, isIdle = true), observer.latest)
        assertEquals(listOf("profile-save"), observer.appeared)
    }

    @Test
    fun identityChangeDuringTransitionDisposesOldContentBeforeLatestIdentitySettles() = runAnimationTest {
        val observer = RecordingObserver()
        var identity by mutableStateOf("first-save")
        var visible by mutableStateOf(true)
        setObservedContent(observer) {
            NativeSaveConfirmation(visible = visible, identity = identity)
        }
        runOnIdle { visible = false }

        runOnIdle {
            visible = true
            identity = "second-save"
        }
        onNodeWithContentDescription("first-save").assertDoesNotExist()
        waitForIdle()
        onNodeWithContentDescription("second-save").assertIsDisplayed()
        assertEquals(observer.states.toString(), TransitionState(visible = true, isIdle = true), observer.latest)
        assertEquals(listOf("first-save"), observer.disposed)
        assertEquals(listOf("first-save", "second-save"), observer.appeared)
    }

    @Test
    fun exitFinishesAndRemovesContentWhenVisibilityChanges() = runAnimationTest {
        val observer = RecordingObserver()
        var saved by mutableStateOf(true)
        setObservedContent(observer) {
            NativeSaveConfirmation(saved, "profile-save")
        }
        runOnIdle { saved = false }
        waitForIdle()
        onNodeWithContentDescription("profile-save").assertDoesNotExist()
        assertEquals(observer.states.toString(), TransitionState(visible = false, isIdle = true), observer.latest)
        assertEquals(listOf("profile-save"), observer.disposed)
    }

    @Test
    fun zeroDurationScaleSkipsMotionForBothEnterAndExit() = runAnimationTest {
        motionScale.scaleFactor = 0f
        val observer = RecordingObserver()
        var saved by mutableStateOf(false)
        setObservedContent(observer) {
            NativeSaveConfirmation(saved, "profile-save")
        }
        waitForIdle()
        assertEquals(observer.states.toString(), TransitionState(visible = false, isIdle = true), observer.latest)
        onNodeWithContentDescription("profile-save").assertDoesNotExist()

        runOnIdle { saved = true }
        waitForIdle()
        onNodeWithContentDescription("profile-save").assertIsDisplayed()
        assertEquals(observer.states.toString(), TransitionState(visible = true, isIdle = true), observer.latest)

        runOnIdle { saved = false }
        waitForIdle()
        onNodeWithContentDescription("profile-save").assertDoesNotExist()
        assertEquals(observer.states.toString(), TransitionState(visible = false, isIdle = true), observer.latest)
        assertEquals(listOf("profile-save"), observer.disposed)
    }

    @Test
    fun leavingCompositionCancelsTransitionAndDisposesContent() = runAnimationTest {
        val observer = RecordingObserver()
        var showScreen by mutableStateOf(true)
        setObservedContent(observer) {
            if (showScreen) {
                refract.generated.SaveConfirmationScreen(
                    saved = true,
                    onSavedChange = {},
                )
            }
        }
        onNodeWithContentDescription("profile-save").assertIsDisplayed()

        runOnIdle { showScreen = false }
        onNodeWithContentDescription("profile-save").assertDoesNotExist()
        assertEquals(listOf("profile-save"), observer.disposed)
    }

    private val motionScale = TestMotionDurationScale(1f)

    private fun runAnimationTest(block: AndroidComposeUiTest<ComponentActivity>.() -> Unit) =
        runAndroidComposeUiTest<ComponentActivity>(
            effectContext = StandardTestDispatcher() + motionScale,
            block = block,
        )

    private fun AndroidComposeUiTest<ComponentActivity>.setObservedContent(
        observer: RecordingObserver,
        content: @androidx.compose.runtime.Composable () -> Unit,
    ) {
        setContent {
            CompositionLocalProvider(LocalSaveConfirmationObserver provides observer) {
                content()
            }
        }
    }

    private class TestMotionDurationScale(override var scaleFactor: Float) : MotionDurationScale

    private data class TransitionState(val visible: Boolean, val isIdle: Boolean)

    private class RecordingObserver : SaveConfirmationObserver {
        val appeared = mutableListOf<String>()
        val disposed = mutableListOf<String>()
        val states = mutableListOf<TransitionState>()
        val latest: TransitionState?
            get() = states.lastOrNull()

        override fun onAppear(identity: String) {
            appeared += identity
        }

        override fun onDispose(identity: String) {
            disposed += identity
        }

        override fun onTransitionStateChanged(visible: Boolean, isIdle: Boolean) {
            states += TransitionState(visible, isIdle)
        }
    }
}
