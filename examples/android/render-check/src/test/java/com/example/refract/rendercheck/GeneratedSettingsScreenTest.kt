package com.example.refract.rendercheck

import android.graphics.Bitmap
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertIsToggleable
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.printToString
import java.io.File
import java.io.FileOutputStream
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import refract.generated.SettingsModel
import refract.generated.SettingsScreen

/**
 * Native JVM Compose verification of the actual CLI-generated settings screen.
 *
 * These are Robolectric-rendered JVM captures, not device or emulator screenshots
 * and not visual parity or performance measurements. No hand-written replacement
 * for the generated screen participates in these tests.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w400dp-h800dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class GeneratedSettingsScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private lateinit var model: RecordingSettingsModel
    private var darkTheme by mutableStateOf(false)

    @Test
    fun toggleHasNativeSemanticsAndDrivesItsBinding() {
        renderGeneratedScreen()

        compose.onNodeWithText("Profile").assertIsDisplayed()
        compose.onNodeWithText("Example user").assertIsDisplayed()
        compose.onNodeWithText("Preferences").assertIsDisplayed()
        compose.onNodeWithText("Notifications").assertIsDisplayed()

        val switch = compose.onNode(isSwitch())
        switch.assertIsDisplayed()
            .assertIsToggleable()
            .assertIsOff()
            .assertHasClickAction()

        switch.performClick()
        compose.waitForIdle()
        switch.assertIsOn()
        assertEquals(listOf(true), model.notificationChanges)

        switch.performClick()
        compose.waitForIdle()
        switch.assertIsOff()
        assertEquals(listOf(true, false), model.notificationChanges)
    }

    @Test
    fun generatedRowsExposeTheirRelationshipWithoutInventedSemantics() {
        renderGeneratedScreen()

        val labelNode = compose.onNodeWithText("Notifications").fetchSemanticsNode()
        val switchNode = compose.onNode(isSwitch()).fetchSemanticsNode()
        assertTrue(
            "Notifications label must be on the switch row",
            labelNode.boundsInRoot.overlapsVertically(switchNode.boundsInRoot),
        )

        // The row's Text and Switch remain separate semantics nodes. This is an
        // observation for the accessibility workstream, not a test-side merger.
        assertNotEquals(labelNode.id, switchNode.id)
        assertTrue(labelNode.config.any { entry -> entry.value == "Notifications" })
    }

    @Test
    fun textModelAndSaveStateReachTheGeneratedScreen() {
        renderGeneratedScreen()

        compose.onNode(hasSetTextAction()).performTextInput("Ada")
        compose.waitForIdle()
        compose.onNodeWithText("Ada", substring = true).assertIsDisplayed()

        compose.activity.runOnUiThread { model.updateTitle("Updated from the native model") }
        compose.waitForIdle()
        compose.onNodeWithText("Updated from the native model").assertIsDisplayed()

        compose.onNodeWithText("Save").assertHasClickAction().performClick()
        compose.waitForIdle()
        assertEquals(1, model.saveCount)
    }

    @Test
    fun generatedScreenCapturesLightAndDarkNativeJvmRendering() {
        renderGeneratedScreen()
        val light = renderAndCapture(dark = false)
        val dark = renderAndCapture(dark = true)
        assertTrue("Light capture must contain rendered pixels", light.file.length() > 1_000)
        assertTrue("Dark capture must contain rendered pixels", dark.file.length() > 1_000)
        assertTrue("Light capture must contain multiple colors", light.distinctColors > 10)
        assertTrue("Dark capture must contain multiple colors", dark.distinctColors > 10)
        assertNotEquals("Light and dark themes must change rendered pixels", light.pixels, dark.pixels)

        val semantics = compose.onRoot().printToString(maxDepth = Int.MAX_VALUE)
        File(outputDirectory(), "native-jvm-compose-dark-semantics.txt").writeText(semantics)
        assertTrue(semantics.contains("Role = 'Switch'"))
        assertTrue(semantics.contains("ToggleableState = Off"))
        assertTrue(semantics.contains("Text = '[Notifications]'"))
    }

    private fun renderAndCapture(dark: Boolean): Capture {
        compose.activity.runOnUiThread { darkTheme = dark }
        compose.waitForIdle()
        shadowOf(Looper.getMainLooper()).idle()
        compose.onNodeWithText("Example user").assertIsDisplayed()
        compose.onNode(isSwitch()).assertIsOff()
        compose.onRoot().assertIsDisplayed()

        val name = if (dark) "native-jvm-compose-dark.png" else "native-jvm-compose-light.png"
        val output = File(outputDirectory(), name)
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
        FileOutputStream(output).use { stream ->
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream))
        }
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        check(output.isFile && output.length() > 0) { "Empty Native JVM Compose capture: $name" }
        return Capture(output, pixels, pixels.distinct().size)
    }

    private fun renderGeneratedScreen() {
        model = RecordingSettingsModel()
        darkTheme = false
        compose.setContent {
            // This only supplies a native Material theme and a deterministic
            // capture boundary. SettingsScreen itself is the CLI-generated one.
            MaterialTheme(colorScheme = if (darkTheme) darkColorScheme() else lightColorScheme()) {
                Surface(modifier = Modifier.fillMaxSize().testTag("capture-surface")) {
                    SettingsScreen(
                        model = model,
                        notificationsEnabled = model.notificationsEnabled,
                        onNotificationsEnabledChange = { model.onNotificationsEnabledChange(it) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }
        compose.waitForIdle()
    }

    private fun outputDirectory(): File {
        val directory = File(requireNotNull(System.getProperty("refract.render.output")))
        check(directory.isDirectory || directory.mkdirs()) { "Cannot create render output directory" }
        return directory
    }
}

private class RecordingSettingsModel : SettingsModel {
    private val titleState = mutableStateOf("Example user")
    var notificationsEnabled by mutableStateOf(false)
        private set
    val notificationChanges = mutableListOf<Boolean>()
    var saveCount = 0
        private set

    override val title: State<String>
        get() = titleState

    override fun save() {
        saveCount += 1
    }

    fun updateTitle(value: String) {
        titleState.value = value
    }

    fun onNotificationsEnabledChange(value: Boolean) {
        notificationChanges += value
        notificationsEnabled = value
    }
}

private class Capture(val file: File, val pixels: IntArray, val distinctColors: Int) {
    override fun equals(other: Any?): Boolean = other is Capture && pixels.contentEquals(other.pixels)
    override fun hashCode(): Int = pixels.contentHashCode()
}

private fun isSwitch(): SemanticsMatcher = SemanticsMatcher("native Switch role") { node ->
    node.config.getOrNull(SemanticsProperties.Role) == Role.Switch
}

private fun SemanticsNodeInteraction.fetchBounds(): androidx.compose.ui.geometry.Rect =
    fetchSemanticsNode().boundsInRoot

private fun androidx.compose.ui.geometry.Rect.overlapsVertically(other: androidx.compose.ui.geometry.Rect): Boolean =
    top < other.bottom && bottom > other.top
