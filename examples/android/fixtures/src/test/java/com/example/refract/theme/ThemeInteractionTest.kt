package com.example.refract.theme

import android.app.Application
import android.content.res.Configuration
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.foundation.interaction.FocusInteraction
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.AndroidComposeTestRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.core.content.ContextCompat
import example.design.AppInteractionColors
import example.design.ThemedSettingsAction
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
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import refract.generated.ThemedSettingsControl

/**
 * Real Compose on Robolectric using the CLI-generated component and its app-owned native host.
 * These are Native JVM behavior/capture results, not emulator/device or performance evidence.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w400dp-h800dp-xxhdpi", application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ThemeInteractionTest {
    @get:Rule
    val compose = AndroidComposeTestRule(
        activityRule = TestRule { base, _ -> base },
        activityProvider = {
            Robolectric.buildActivity(ComponentActivity::class.java)
                .create().start().postCreate(null).resume().visible().windowFocusChanged(true).get()
        },
    )

    @Test
    fun actualPressAndFocusResolveTheirOwnResourcesAndDisabledWins() {
        val resources = ApplicationProvider.getApplicationContext<Application>().resources
        lateinit var source: MutableInteractionSource
        var enabled by mutableStateOf(true)
        val observedColor = mutableIntStateOf(0)
        compose.setContent {
            val interactionSource = remember { MutableInteractionSource() }
            source = interactionSource
            val pressed = interactionSource.collectIsPressedAsState().value
            val focused = interactionSource.collectIsFocusedAsState().value
            // This is the same composition and the same source consumed by the app host below.
            observedColor.intValue = AppInteractionColors.resolve(
                enabled = enabled,
                pressed = pressed,
                focused = focused,
                normal = refract.generated.R.color.theme_action_normal,
                pressedColor = refract.generated.R.color.theme_action_pressed,
                focusedColor = refract.generated.R.color.theme_action_focused,
                disabledColor = refract.generated.R.color.theme_action_disabled,
            ).toArgb()
            ThemedSettingsAction(interactionSource, enabled = enabled, onClick = {})
        }
        compose.waitForIdle()
        assertEquals(ContextCompat.getColor(compose.activity,refract.generated.R.color.theme_action_normal), observedColor.intValue)
        val press = PressInteraction.Press(Offset.Zero)
        val focus = FocusInteraction.Focus()
        compose.activity.runOnUiThread { source.tryEmit(press) }
        compose.waitForIdle()
        assertEquals(ContextCompat.getColor(compose.activity,refract.generated.R.color.theme_action_pressed), observedColor.intValue)
        compose.activity.runOnUiThread { source.tryEmit(focus) }
        compose.waitForIdle()
        assertEquals("Pressed wins while both actual interactions are active",
            ContextCompat.getColor(compose.activity,refract.generated.R.color.theme_action_pressed), observedColor.intValue)
        compose.activity.runOnUiThread { source.tryEmit(PressInteraction.Release(press)) }
        compose.waitForIdle()
        assertEquals(ContextCompat.getColor(compose.activity,refract.generated.R.color.theme_action_focused), observedColor.intValue)
        compose.activity.runOnUiThread { enabled = false }
        compose.waitForIdle()
        assertEquals("Disabled wins over the still-focused control",
            ContextCompat.getColor(compose.activity,refract.generated.R.color.theme_action_disabled), observedColor.intValue)
    }

    @Test
    fun nightResourcesChangeActualGeneratedRendering() {
        var night by mutableStateOf(false)
        compose.setContent {
            val context = LocalContext.current
            val configuration = Configuration(context.resources.configuration).apply {
                uiMode = if (night) {
                    (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or Configuration.UI_MODE_NIGHT_YES
                } else {
                    (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or Configuration.UI_MODE_NIGHT_NO
                }
            }
            val themedContext = remember(configuration) { context.createConfigurationContext(configuration) }
            CompositionLocalProvider(LocalContext provides themedContext) {
                ThemedSettingsControl(
                    isEnabled = true, onIsEnabledChange = {},
                    isPressed = false, onIsPressedChange = {},
                    isFocused = false, onIsFocusedChange = {},
                )
            }
        }
        compose.onNodeWithText("Appearance and notifications").assertIsDisplayed()
        val light = capturePixels("native-jvm-theme-light.png")
        compose.activity.runOnUiThread { night = true }
        compose.waitForIdle()
        compose.onNodeWithText("Appearance and notifications").assertIsDisplayed()
        val dark = capturePixels("native-jvm-theme-dark.png")
        assertNotEquals("Night resources change actual generated pixels", light, dark)
    }

    @Test
    fun enlargedFontChangesActualGeneratedLayout() {
        val normal: Bounds
        val large: Bounds
        var fontScale by mutableStateOf(1f)
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(density.density, fontScale = fontScale),
            ) {
                Box(Modifier.fillMaxWidth().padding(16.dp)) {
                    ThemedSettingsControl(
                        isEnabled = true,
                        onIsEnabledChange = {},
                        isPressed = false,
                        onIsPressedChange = {},
                        isFocused = false,
                        onIsFocusedChange = {},
                    )
                }
            }
        }
        normal = measureAndCapture("native-jvm-theme-light.png")
        compose.activity.runOnUiThread { fontScale = 2f }
        compose.waitForIdle()
        large = measureAndCapture("native-jvm-theme-large-font.png")
        assertTrue("2x fontScale increases actual generated text height: ${normal.height} vs ${large.height}",
            large.height > normal.height * 1.5f)
        File(outputDirectory(), "native-jvm-theme-bounds.txt").writeText(
            "Native JVM Compose; not a device or emulator result\ndefault fontScale height=${normal.height}\n" +
                "2x fontScale height=${large.height}\n",
        )
        assertTrue("Large-font capture contains rendered pixels",
            File(outputDirectory(), "native-jvm-theme-large-font.png").length() > 1_000)
    }

    private data class Bounds(val width: Float, val height: Float)

    private fun measureAndCapture(name: String): Bounds {
        compose.onNodeWithText("Appearance and notifications").assertIsDisplayed()
        val bounds = compose.onNodeWithText("Appearance and notifications").fetchSemanticsNode().boundsInRoot
        val output = File(outputDirectory(), name)
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
        FileOutputStream(output).use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        return Bounds(bounds.width, bounds.height)
    }

    private fun capturePixels(name: String): List<Int> {
        val output = File(outputDirectory(), name)
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
        FileOutputStream(output).use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        return pixels.toList()
    }

    private fun outputDirectory(): File {
        val directory = File(requireNotNull(System.getProperty("refract.render.output")))
        check(directory.isDirectory || directory.mkdirs())
        return directory
    }
}
