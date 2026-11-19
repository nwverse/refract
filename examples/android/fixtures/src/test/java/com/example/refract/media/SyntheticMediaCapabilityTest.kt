package com.example.refract.media

import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.key
import androidx.compose.ui.test.AndroidComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.v2.runAndroidComposeUiTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import refract.generated.CameraCapabilityScreen
import refract.generated.PlaybackCapabilityScreen
import refract.generated.ShareCapabilityScreen

/** Real Compose on Robolectric: Native JVM only, not a real media or permission implementation. */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SyntheticMediaCapabilityTest {
    @Test
    fun absenceAndPermissionStatesNeverPlaceAPlaybackComponent() = runMediaTest {
        val controller = SyntheticMediaController()
        setContent { GeneratedMediaHost(controller) }
        onNodeWithText("Playback capability unavailable").assertExists()
        onNodeWithTag("media_playback_ready").assertDoesNotExist()
        controller.select(SyntheticMediaKind.playback, SyntheticPhase.permissionRequired)
        onNodeWithText("Playback permission requires app handling").assertExists()
        onNodeWithTag("media_playback_ready").assertDoesNotExist()
        controller.select(SyntheticMediaKind.playback, SyntheticPhase.permissionDenied)
        onNodeWithText("Playback permission denied").assertExists()
        onNodeWithTag("media_playback_ready").assertDoesNotExist()
        assertTrue(controller.actions.isEmpty())
    }

    @Test
    fun cameraApprovalCancelRejectsALateSyntheticResult() = runMediaTest {
        val controller = SyntheticMediaController()
        setContent { GeneratedMediaHost(controller) }
        controller.select(SyntheticMediaKind.camera, SyntheticPhase.approvalRequired)
        onNodeWithText("Request synthetic camera approval").performClick()
        assertEquals(listOf("approve:synthetic-camera-1:2"), controller.actions)
        onNodeWithTag("media_camera_cancel").assertDoesNotExist()
        onNodeWithText("Cancel synthetic camera").performClick()
        assertEquals(
            listOf("approve:synthetic-camera-1:2", "cancel:synthetic-camera-1:2"),
            controller.actions,
        )
        onNodeWithText("Synthetic camera cancelled").assertExists()
        controller.deliverSyntheticApproval()
        onNodeWithText("Synthetic camera cancelled").assertExists()
        onNodeWithTag("media_camera_ready").assertDoesNotExist()
        assertEquals(SyntheticPhase.cancelled, controller.request.phase)
    }

    @Test
    fun sameRevisionIdentifierReplacementRejectsTheOldApprovalThroughGeneratedScreen() = runMediaTest {
        val controller = SyntheticMediaController()
        setContent { GeneratedMediaHost(controller) }
        controller.select(SyntheticMediaKind.camera, SyntheticPhase.approvalRequired)
        onNodeWithText("Request synthetic camera approval").performClick()
        val revision = controller.request.revision
        runOnIdle {
            controller.replaceForApprovalCorrelation(
                SyntheticMediaKind.camera,
                "synthetic-camera-replacement",
            )
        }
        onNodeWithText("Camera approval required").assertExists()
        assertEquals(revision, controller.request.revision)
        controller.deliverSyntheticApproval()
        onNodeWithText("Camera approval required").assertExists()
        onNodeWithTag("media_camera_ready").assertDoesNotExist()
        assertEquals(SyntheticPhase.approvalRequired, controller.request.phase)
        assertEquals(listOf("approve:synthetic-camera-1:2"), controller.actions)
    }

    @Test
    fun sameRevisionKindReplacementRejectsTheOldApprovalThroughGeneratedScreen() = runMediaTest {
        val controller = SyntheticMediaController()
        setContent { GeneratedMediaHost(controller) }
        controller.select(SyntheticMediaKind.camera, SyntheticPhase.approvalRequired)
        onNodeWithText("Request synthetic camera approval").performClick()
        val revision = controller.request.revision
        runOnIdle {
            controller.replaceForApprovalCorrelation(
                SyntheticMediaKind.share,
                "synthetic-share-replacement",
            )
        }
        onNodeWithText("Share approval required").assertExists()
        assertEquals(revision, controller.request.revision)
        controller.deliverSyntheticApproval()
        onNodeWithText("Share approval required").assertExists()
        onNodeWithTag("media_share_ready").assertDoesNotExist()
        onNodeWithTag("media_camera_ready").assertDoesNotExist()
        assertEquals(SyntheticPhase.approvalRequired, controller.request.phase)
        assertEquals(listOf("approve:synthetic-camera-1:2"), controller.actions)
    }

    @Test
    fun shareReadyIsOnlyAppSelectedAndCancelsThroughTypedAction() = runMediaTest {
        val appeared = mutableListOf<String>()
        val disposed = mutableListOf<String>()
        val controller = SyntheticMediaController()
        setContent {
            CompositionLocalProvider(
                LocalSyntheticMediaObservation provides SyntheticMediaObservation(
                    onAppear = { kind, revision -> appeared += "$kind:$revision" },
                    onDispose = { kind, revision -> disposed += "$kind:$revision" },
                )
            ) {
                GeneratedMediaHost(controller)
            }
        }
        controller.select(SyntheticMediaKind.share, SyntheticPhase.approvalRequired)
        onNodeWithText("Request synthetic share approval").performClick()
        controller.deliverSyntheticApproval()
        onNodeWithTag("media_share_ready").assertExists()
        onNodeWithText("Cancel synthetic share").performClick()
        onNodeWithText("Synthetic share cancelled").assertExists()
        onNodeWithTag("media_share_ready").assertDoesNotExist()
        runOnIdle {
            assertEquals(listOf("share:2"), appeared)
            assertEquals(listOf("share:2"), disposed)
        }
        assertEquals(
            listOf("approve:synthetic-share-1:2", "cancel:synthetic-share-1:2"),
            controller.actions,
        )
    }

    @Test
    fun allThreeCapabilitiesHaveExplicitSyntheticAbsenceAndApprovalBoundaries() = runMediaTest {
        val controller = SyntheticMediaController()
        setContent { GeneratedMediaHost(controller) }
        for (kind in listOf(SyntheticMediaKind.camera, SyntheticMediaKind.share)) {
            val name = kind.name
            controller.select(kind, SyntheticPhase.unavailable)
            val title = name.replaceFirstChar { it.uppercase() }
            onNodeWithText("$title capability unavailable").assertExists()
            onNodeWithTag("media_${name}_ready").assertDoesNotExist()
            controller.select(kind, SyntheticPhase.permissionRequired)
            onNodeWithText("$title permission requires app handling").assertExists()
            controller.select(kind, SyntheticPhase.permissionDenied)
            onNodeWithText("$title permission denied").assertExists()
            controller.select(kind, SyntheticPhase.approvalRequired)
            onNodeWithText("Request synthetic $name approval").performClick()
            controller.deliverSyntheticApproval()
            onNodeWithTag("media_${name}_ready").assertExists()
            onNodeWithText("Cancel synthetic $name").performClick()
            onNodeWithText("Synthetic $name cancelled").assertExists()
        }
    }

    private fun runMediaTest(block: AndroidComposeUiTest<ComponentActivity>.() -> Unit) =
        runAndroidComposeUiTest<ComponentActivity>(block = block)
}

@Composable
private fun GeneratedMediaHost(controller: SyntheticMediaController) {
    key(controller.screenRevision) {
        val request = controller.request
        when (request.kind) {
            SyntheticMediaKind.playback -> PlaybackCapabilityScreen(
                state = controller.playbackState(),
                identifier = request.identifier,
                revision = request.revision,
                model = controller,
            )
            SyntheticMediaKind.camera -> CameraCapabilityScreen(
                state = controller.cameraState(),
                identifier = request.identifier,
                revision = request.revision,
                model = controller,
            )
            SyntheticMediaKind.share -> ShareCapabilityScreen(
                state = controller.shareState(),
                identifier = request.identifier,
                revision = request.revision,
                model = controller,
            )
        }
    }
}
