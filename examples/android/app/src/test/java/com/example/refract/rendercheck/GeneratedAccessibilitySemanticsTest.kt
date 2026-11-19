package com.example.refract.rendercheck

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.AndroidComposeTestRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.printToString
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.test.core.app.ApplicationProvider
import com.example.refract.R
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestRule
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import refract.generated.accessibility.AccessibilityActionsTraversal
import refract.generated.accessibility.SyncAccessibilityModel

/** Native JVM Compose checks of the exact CLI-generated fixture; no screen-reader/device evidence. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w400dp-h800dp-xxhdpi", application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class GeneratedAccessibilitySemanticsTest {
    @get:Rule
    val compose = accessibilityComposeRule()

    @Test
    fun localizedTextCustomActionsAndOrdinaryAlternativesWork() {
        val model = RecordingSyncAccessibilityModel()
        render(model)
        val sync = compose.onNodeWithTag("sync_now", useUnmergedTree = true).fetchSemanticsNode()
        assertEquals(
            listOf("Synchronize settings Updates settings from the server"),
            sync.config.getOrNull(SemanticsProperties.ContentDescription),
        )
        assertEquals("Current status: Idle", sync.config.getOrNull(SemanticsProperties.StateDescription))
        val action = sync.config.getOrNull(SemanticsActions.CustomActions)
            .orEmpty().single()
        assertEquals("Start synchronization", action.label)
        assertTrue("The native action must report successful handling", action.action())
        assertEquals(1, model.syncCount)

        compose.onNodeWithTag("sync_now", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("sync_details", useUnmergedTree = true)
            .assertHasClickAction().performClick()
        assertEquals(2, model.syncCount)
        assertEquals(1, model.detailsCount)
        model.statusState.value = "Up to date"
        compose.waitForIdle()
        assertEquals(
            "Current status: Up to date",
            compose.onNodeWithTag("sync_now", useUnmergedTree = true)
                .fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription),
        )
    }

    @Test
    fun directChildrenExposeTheirDeclaredTraversalMetadata() {
        render(RecordingSyncAccessibilityModel())
        listOf("sync_now" to 0f, "sync_details" to 1f).forEach { (tag, index) ->
            val config = compose.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config
            assertEquals(index, config.getOrNull(SemanticsProperties.TraversalIndex))
            assertEquals(true, config.getOrNull(SemanticsProperties.IsTraversalGroup))
        }
        val group = compose.onAllNodes(isTraversalGroup(), useUnmergedTree = true)
            .fetchSemanticsNodes().first()
        assertTrue("The named direct children must remain in the native semantics tree", group.children.isNotEmpty())
        File(outputDirectory(), "native-jvm-accessibility-semantics.txt").writeText(
            compose.onRoot(useUnmergedTree = true).printToString(maxDepth = Int.MAX_VALUE),
        )
    }

    @Test
    @Config(sdk = [35], qualifiers = "w400dp-h800dp-xxhdpi")
    fun mergedNodesKeepLabelsActionsAndAlternatives() {
        val model = RecordingSyncAccessibilityModel()
        render(model)
        val sync = compose.onNodeWithTag("sync_now")
        val config = sync.fetchSemanticsNode().config
        assertEquals(
            listOf("Synchronize settings Updates settings from the server"),
            config.getOrNull(SemanticsProperties.ContentDescription),
        )
        assertEquals("Start synchronization", config.getOrNull(SemanticsActions.CustomActions)?.single()?.label)
        compose.onNodeWithTag("sync_details").assertHasClickAction().performClick()
        assertEquals(1, model.detailsCount)
    }

    @Test
    @Config(sdk = [35], qualifiers = "en-rES-w400dp-h800dp-xxhdpi")
    fun spanishResourcesAreReadFromTheAppCatalog() {
        val resources = ApplicationProvider.getApplicationContext<Application>()
            .createConfigurationContext(
                ApplicationProvider.getApplicationContext<Application>().resources.configuration.apply {
                    setLocale(Locale.forLanguageTag("es"))
                },
            ).resources
        assertEquals("Sincronizar ajustes", resources.getString(R.string.accessibility_sync_label))
        assertEquals("Iniciar sincronización", resources.getString(R.string.accessibility_sync_action))
        render(RecordingSyncAccessibilityModel())
        compose.onRoot().captureNativeJvm("native-jvm-accessibility-spanish")
    }

    @Test
    @Config(sdk = [35], qualifiers = "w400dp-h800dp-xxhdpi")
    fun enlargedNativeTextRemainsVisibleAndChangesRendering() {
        val model = RecordingSyncAccessibilityModel()
        render(model, largeText = true)
        val sync = compose.onNodeWithTag("sync_now")
        File(outputDirectory(), "native-jvm-accessibility-large-semantics.txt").writeText(
            compose.onRoot().printToString(maxDepth = Int.MAX_VALUE),
        )
        sync.assertIsDisplayed()
        assertTrue(
            "Large text must retain a nonzero native control hit area",
            sync.fetchSemanticsNode().boundsInRoot.height > 0,
        )
        val captureFile = compose.onRoot().captureNativeJvm("native-jvm-accessibility-large-text")
        assertTrue(captureFile.length() > 1_000)
        assertNotEquals("Enlarged rendering must not be an empty capture", 0, captureFile.length())
    }

    private fun render(model: SyncAccessibilityModel, largeText: Boolean = false) {
        val configuration = ApplicationProvider.getApplicationContext<Application>().resources.configuration
        configuration.fontScale = if (largeText) 2.0f else 1.0f
        val fontContext = ApplicationProvider.getApplicationContext<Application>().createConfigurationContext(configuration)
        compose.setContent {
            CompositionLocalProvider(
                androidx.compose.ui.platform.LocalContext provides fontContext,
            ) {
                MaterialTheme {
                    Surface(modifier = Modifier.fillMaxWidth()) {
                        AccessibilityActionsTraversal(model = model)
                    }
                }
            }
        }
        compose.waitForIdle()
    }
}

private class RecordingSyncAccessibilityModel : SyncAccessibilityModel {
    val statusState = mutableStateOf("Idle")
    override val syncStatus: State<String> get() = statusState
    var syncCount = 0
        private set
    var detailsCount = 0
        private set
    override fun syncNow() { syncCount += 1 }
    override fun showDetails() { detailsCount += 1 }
}

private fun accessibilityComposeRule() = AndroidComposeTestRule(
    activityRule = TestRule { base, _ -> base },
    activityProvider = {
        Robolectric.buildActivity(RenderCheckActivity::class.java)
            .create().start().postCreate(null).resume().visible().windowFocusChanged(true).get()
    },
)

private fun androidx.compose.ui.test.SemanticsNodeInteraction.captureNativeJvm(name: String): File {
    val output = File(outputDirectory(), "$name.png")
    val bitmap = captureToImage().asAndroidBitmap()
    FileOutputStream(output).use { stream -> check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) }
    return output
}

private fun outputDirectory(): File {
    val directory = File(requireNotNull(System.getProperty("refract.render.output")))
    check(directory.isDirectory || directory.mkdirs())
    return directory
}

private fun isTraversalGroup(): SemanticsMatcher = SemanticsMatcher("native traversal group") {
    it.config.getOrNull(SemanticsProperties.IsTraversalGroup) == true && it.children.isNotEmpty()
}
