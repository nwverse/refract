@file:OptIn(androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi::class)

package com.example.refract.rendercheck

import android.app.Application
import android.graphics.Bitmap
import android.os.Looper
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.windowsizeclass.WindowSizeClass
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.v2.AndroidComposeTestRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.printToString
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.test.core.app.ApplicationProvider
import java.io.File
import java.io.FileOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestRule
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import com.example.refract.R
import refract.generated.AdaptiveNavigationScreen
import refract.generated.AdaptiveNavigationScreenDestinations
import refract.generated.AdaptiveRoute
import refract.generated.AdaptiveSettingsModel
import refract.generated.AdaptiveSettingsScreen

/** Native JVM Compose evidence of the exact staged CLI-generated adaptive screen. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w400dp-h800dp-xhdpi", application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AdaptiveSettingsScreenTest {
    @get:Rule
    val compose = AndroidComposeTestRule(
        activityRule = TestRule { base, _ -> base },
        activityProvider = {
            Robolectric.buildActivity(RenderCheckActivity::class.java)
                .create().start().postCreate(null).resume().visible().windowFocusChanged(true).get()
        },
    )

    private lateinit var model: RecordingAdaptiveModel
    private var fontScale = mutableStateOf(1f)
    private var widthClass = mutableStateOf(WindowWidthSizeClass.Compact)
    private lateinit var controller: androidx.navigation.NavHostController

    @Test
    fun adaptiveResourcesAndWindowClassificationAreNative() {
        val resources = ApplicationProvider.getApplicationContext<Application>().resources
        assertEquals("Notifications", resources.getString(R.string.settings_notifications))
        assertEquals("Open details", resources.getString(R.string.adaptive_open))
        assertEquals(
            WindowWidthSizeClass.Compact,
            WindowSizeClass.calculateFromSize(DpSize(599.dp, 800.dp)).widthSizeClass,
        )
        assertEquals(
            WindowWidthSizeClass.Medium,
            WindowSizeClass.calculateFromSize(DpSize(600.dp, 800.dp)).widthSizeClass,
        )
        assertEquals(
            WindowWidthSizeClass.Expanded,
            WindowSizeClass.calculateFromSize(DpSize(840.dp, 800.dp)).widthSizeClass,
        )
    }

    @Test
    fun resizeAndTextScalingRetainContentStateAndNavigation() {
        renderAdaptiveHost()

        compose.onAllNodesWithText("Example user").assertCountEquals(2)
        compose.onNode(hasSetTextAction()).performTextInput("Preserved name")
        compose.onNode(isSwitch()).assertIsOff().performClick()
        compose.onNode(isSwitch()).assertIsOn()
        compose.onNodeWithText("Preserved name", substring = true).assertIsDisplayed()
        val compact = capture("adaptive-compact")

        setWindowClass(WindowWidthSizeClass.Expanded)
        compose.onNodeWithText("Preserved name", substring = true).assertIsDisplayed()
        compose.onNode(isSwitch()).assertIsOn()
        assertEquals(1, currentModel().notificationChanges.size)
        val expanded = capture("adaptive-expanded")
        assertNotEquals("Resize must change the native rendered layout", compact, expanded)

        setFontScale(2f)
        compose.onNodeWithText("Preserved name", substring = true).assertIsDisplayed()
        compose.onNode(isSwitch()).assertIsOn()
        val expandedLargeText = capture("adaptive-expanded-large-text")
        assertNotEquals("Native text scale must change rendered pixels", expanded, expandedLargeText)

        // The root and pushed destination keep the exact same app model instance.
        compose.onNodeWithText("Open details").performClick()
        compose.onNodeWithText("Example user").assertIsDisplayed()
        setWindowClass(WindowWidthSizeClass.Compact)
        setFontScale(1f)
        compose.onNodeWithText("Example user").assertIsDisplayed()
        // Robolectric's test Activity does not dispatch a physical system-back
        // button. Drive the same native controller's pop operation explicitly.
        compose.activity.runOnUiThread { controller.popBackStack() }
        compose.waitForIdle()
        File(outputDirectory(), "adaptive-after-back-semantics.txt").writeText(
            compose.onRoot(useUnmergedTree = true).printToString(maxDepth = Int.MAX_VALUE)
        )
        compose.onAllNodesWithText("Open details").assertCountEquals(1)
        compose.onNodeWithText("Preserved name", substring = true).assertIsDisplayed()
        compose.onNode(isSwitch()).assertIsOn()
        compose.onNodeWithText("Open details").assertIsDisplayed()
    }

    private fun renderAdaptiveHost() {
        model = RecordingAdaptiveModel()
        compose.setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    CompositionLocalProvider(LocalDensity provides Density(
                        LocalDensity.current.density,
                        fontScale.value,
                    )) {
                        val displayName = androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf("") }
                        controller = rememberNavController()
                        NavHost(controller, startDestination = "settings") {
                            composable("settings") {
                                Column {
                                    AdaptiveNavigationScreen(model = model, onPathNavigate = {
                                        model.navigationCount += 1
                                        controller.navigate(AdaptiveRoute.detail.name)
                                    })
                                    AdaptiveSettingsScreen(
                                        model = model,
                                        widthSizeClass = widthClass.value,
                                        notificationsEnabled = model.notificationsEnabled,
                                        onNotificationsEnabledChange = { model.onNotificationsChange(it) },
                                        displayName = displayName.value,
                                        onDisplayNameChange = { displayName.value = it },
                                        modifier = Modifier.fillMaxWidth(),
                                    )
                                }
                            }
                            composable(AdaptiveRoute.detail.name) {
                                AdaptiveNavigationScreenDestinations(
                                    destination = AdaptiveRoute.detail,
                                    model = model,
                                )
                            }
                        }
                    }
                }
            }
        }
        compose.waitForIdle()
    }

    private fun currentModel(): RecordingAdaptiveModel = model

    private fun setWindowClass(value: WindowWidthSizeClass) {
        compose.activity.runOnUiThread { widthClass.value = value }
        compose.waitForIdle()
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun setFontScale(value: Float) {
        compose.activity.runOnUiThread { fontScale.value = value }
        compose.waitForIdle()
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun capture(name: String): IntArray {
        compose.onRoot().assertIsDisplayed()
        val output = File(outputDirectory(), "native-jvm-compose-$name.png")
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
        FileOutputStream(output).use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        assertTrue("Native JVM capture must not be empty", output.length() > 1_000)
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        assertTrue("Native JVM capture must contain multiple colors", pixels.distinct().size > 10)
        return pixels
    }

    private fun outputDirectory(): File {
        val directory = File(requireNotNull(System.getProperty("refract.render.output")))
        check(directory.isDirectory || directory.mkdirs()) { "Cannot create render output directory" }
        return directory
    }
}

private class RecordingAdaptiveModel : AdaptiveSettingsModel {
    private val titleState = mutableStateOf("Example user")
    var notificationsEnabled by mutableStateOf(false)
    val notificationChanges = mutableListOf<Boolean>()
    var navigationCount = 0

    override val title: State<String> get() = titleState
    override fun save() {}
    fun onNotificationsChange(value: Boolean) {
        notificationChanges += value
        notificationsEnabled = value
    }
}

private fun isSwitch(): SemanticsMatcher = SemanticsMatcher("native Switch role") { node ->
    node.config.getOrNull(SemanticsProperties.Role) == androidx.compose.ui.semantics.Role.Switch
}
