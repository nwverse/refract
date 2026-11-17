package com.example.refract.document

import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.AndroidComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.v2.runAndroidComposeUiTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import refract.generated.DocumentPreviewState
import refract.generated.DocumentPreviewScreen

/** Real Compose on Robolectric: Native JVM, not a device, emulator or performance test. */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SyntheticDocumentPreviewTest {
    @Test
    fun readyShowsOnlyAppDecodedSyntheticTextAndCloseReleasesIt() = runDocumentTest {
        val appeared = mutableListOf<Int>()
        val disposed = mutableListOf<Int>()
        val controller = SyntheticDocumentController(activity ?: error("Document test activity is unavailable"))
        setContent {
            CompositionLocalProvider(
                LocalDecodedSyntheticText provides DecodedSyntheticText(
                    controller.document.decodedText,
                    onAppear = appeared::add,
                    onDispose = disposed::add,
                )
            ) {
                GeneratedDocumentHost(controller)
            }
        }
        runOnIdle {
            controller.authorizeSyntheticTextFixture()
            controller.finishOpening()
        }
        onNodeWithTag("document_body")
            .assertTextEquals(SyntheticDocumentController.SYNTHETIC_DOCUMENT_TEXT)
        assertEquals(DocumentPreviewState.ready, controller.document.state)
        assertTrue(controller.document.uri.toString().contains("/raw/synthetic_document"))
        assertFalse(controller.document.uri.toString().startsWith("http"))

        onNodeWithTag("document_close").performClick()
        onNodeWithText("Document is closed").assertExists()
        onNodeWithTag("document_body").assertDoesNotExist()
        assertEquals(DocumentPreviewState.closed, controller.document.state)
        assertEquals("", controller.document.decodedText)
        val openedRevision = controller.document.revision
        runOnIdle {
            assertEquals(listOf(openedRevision), appeared)
            assertEquals(listOf(openedRevision), disposed)
        }
    }

    @Test
    fun cancellationKeepsDecodedTextOutAndCannotFinishACancelledLoad() = runDocumentTest {
        val controller = SyntheticDocumentController(activity ?: error("Document test activity is unavailable"))
        setContent { GeneratedDocumentHost(controller) }
        runOnIdle { controller.authorizeSyntheticTextFixture() }
        onNodeWithText("Loading document").assertExists()
        onNodeWithTag("document_body").assertDoesNotExist()
        onNodeWithText("Cancel document").performClick()
        onNodeWithText("Document opening was cancelled").assertExists()
        runOnIdle { controller.finishOpening() }
        assertEquals(DocumentPreviewState.cancelled, controller.document.state)
        assertEquals("", controller.document.decodedText)
        onNodeWithTag("document_body").assertDoesNotExist()
    }

    @Test
    fun missingAndUnsupportedAreExplicitWithoutAPreviewCall() = runDocumentTest {
        val controller = SyntheticDocumentController(activity ?: error("Document test activity is unavailable"))
        setContent { GeneratedDocumentHost(controller) }
        runOnIdle { controller.openWithMissingResult() }
        onNodeWithText("Document is missing").assertExists()
        onNodeWithTag("document_body").assertDoesNotExist()
        assertEquals(DocumentPreviewState.missing, controller.document.state)

        runOnIdle { controller.openWithUnsupportedResult() }
        onNodeWithText("Document format is unsupported").assertExists()
        onNodeWithTag("document_body").assertDoesNotExist()
        assertEquals(DocumentPreviewState.unsupported, controller.document.state)
        assertEquals("application/pdf", controller.document.mimeType)
    }

    private fun runDocumentTest(block: AndroidComposeUiTest<ComponentActivity>.() -> Unit) =
        runAndroidComposeUiTest<ComponentActivity>(block = block)

}

@Composable
private fun GeneratedDocumentHost(controller: SyntheticDocumentController) {
    androidx.compose.runtime.key(controller.screenRevision, controller.document.state) {
        val document = controller.document
        DocumentPreviewScreen(
            state = document.state,
            uri = document.uri.toString(),
            displayName = document.displayName,
            mimeType = document.mimeType,
            byteCount = document.byteCount,
            revision = document.revision,
            model = controller,
        )
    }
}
