package com.example.refract.themecheck

import android.app.Application
import android.content.res.Configuration
import android.graphics.Bitmap
import android.view.ContextThemeWrapper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.AndroidComposeTestRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.requestFocus
import androidx.compose.ui.unit.Density
import example.design.ThemedSettingsAction
import java.io.File
import java.io.FileOutputStream
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
import refract.generated.R

/**
 * Native JVM Compose evidence for the real app-owned host and generated control.
 *
 * These are Robolectric rendering and interaction tests, never emulator/device
 * screenshots, screen-reader evidence, cross-platform parity or performance data.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w400dp-h800dp-xxhdpi", application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ThemedSettingsInteractionTest {
    @get:Rule
    val compose = AndroidComposeTestRule(
        activityRule = TestRule { base, _ -> base },
        activityProvider = {
            Robolectric.buildActivity(ThemeCheckActivity::class.java)
                .create()
                .start()
                .postCreate(null)
                .resume()
                .visible()
                .windowFocusChanged(true)
                .get()
        },
    )

    private var enabled by mutableStateOf(true)
    private var fontScale by mutableStateOf(1.0f)
    private var nightMode by mutableStateOf(false)

    @Test
    fun realPressAndFocusReachGeneratedColorArgumentsWithDisabledPrecedence() {
        val source = MutableInteractionSource()
        render(source)
        assertBackgroundColor(R.color.theme_action_normal, "normal")
        capture("normal")

        compose.onNodeWithTag(ACTION).performTouchInput {
            down(center)
            advanceEventTime(500)
        }
        compose.waitForIdle()
        assertBackgroundColor(R.color.theme_action_pressed, "actual press")
        capture("pressed")

        compose.onNodeWithTag(ACTION).performTouchInput { up() }
        compose.waitForIdle()
        assertBackgroundColor(R.color.theme_action_normal, "release")

        compose.onNodeWithTag(ACTION).requestFocus()
        compose.waitForIdle()
        assertBackgroundColor(R.color.theme_action_focused, "actual focus")
        capture("focused")

        compose.activity.runOnUiThread { enabled = false }
        compose.waitForIdle()
        compose.onNodeWithTag(ACTION).assertIsNotEnabled()
        assertBackgroundColor(R.color.theme_action_disabled, "disabled while focused")
        capture("disabled")

        // Keep the same native source in a genuine pressed interaction when
        // the caller disables the control. Disabled must not become pressed.
        val press = PressInteraction.Press(Offset.Zero)
        compose.activity.runOnUiThread {
            source.tryEmit(press)
            enabled = false
        }
        compose.waitForIdle()
        assertBackgroundColor(R.color.theme_action_disabled, "disabled wins over held native press")
        compose.activity.runOnUiThread { source.tryEmit(PressInteraction.Cancel(press)) }
        compose.waitForIdle()

        compose.onNodeWithTag(ACTION).performTouchInput {
            down(center)
            advanceEventTime(500)
        }
        compose.waitForIdle()
        assertBackgroundColor(R.color.theme_action_disabled, "disabled wins over attempted press")
        compose.onNodeWithTag(ACTION).performTouchInput { up() }
    }

    @Test
    fun generatedControlKeepsApplicationNightResources() {
        val source = MutableInteractionSource()
        render(source)
        val light = capture("light")
        assertBackgroundColor(R.color.theme_action_normal, "light normal")

        compose.activity.runOnUiThread { nightMode = true }
        compose.waitForIdle()
        assertBackgroundColor(R.color.theme_action_normal, "dark normal")
        val dark = capture("dark")
        assertNotEquals("Night resources must change the actual rendered pixels", light.pixels, dark.pixels)
        assertTrue("Both captures must contain native rendering", light.file.length() > 1_000 && dark.file.length() > 1_000)
    }

    @Test
    fun enlargedFontScaleChangesGeneratedTextLayout() {
        val source = MutableInteractionSource()
        render(source)
        val ordinary = textBounds()
        capture("font-default")

        compose.activity.runOnUiThread { fontScale = 2.0f }
        compose.waitForIdle()
        val enlarged = textBounds()
        capture("font-large")

        assertTrue(
            "Enlarged native fontScale must change the generated text bounds, not only declare sp: $ordinary -> $enlarged",
            enlarged.height() > ordinary.height() && enlarged.width() > ordinary.width(),
        )
        assertTrue("The generated text remains visible at enlarged type", enlarged.height() > 0)
        compose.onNodeWithText(LABEL).assertIsDisplayed()
    }

    private fun render(source: MutableInteractionSource) {
        enabled = true
        fontScale = 1.0f
        nightMode = false
        compose.setContent {
            // A real Android ContextThemeWrapper supplies the app's resource
            // qualifiers. This is configuration-driven JVM rendering, not a
            // replacement resource resolver or a physical-device settings test.
            val configuration = Configuration(compose.activity.resources.configuration).apply {
                this.fontScale = fontScale
                uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                    if (nightMode) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
            }
            val themedContext = ContextThemeWrapper(compose.activity, 0).apply {
                applyOverrideConfiguration(configuration)
            }
            CompositionLocalProvider(
                LocalContext provides themedContext,
                // Android supplies this density/fontScale pair to Compose on a
                // real configuration change. Replacing only LocalContext does
                // not itself change Compose's LocalDensity.
                LocalDensity provides Density(
                    density = LocalDensity.current.density,
                    fontScale = fontScale,
                ),
            ) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    ThemedSettingsAction(
                        interactionSource = source,
                        enabled = enabled,
                        onClick = {},
                        modifier = Modifier.testTag(ACTION),
                    )
                }
            }
        }
        compose.waitForIdle()
        compose.onNodeWithTag(ACTION).assertIsDisplayed()
    }

    private fun textBounds(): android.graphics.Rect {
        val bounds = android.graphics.Rect()
        // Read the actual generated Text's semantics bounds. No replacement
        // text measurement or screen-specific expected size is introduced.
        val rect = compose.onNodeWithText(LABEL).fetchSemanticsNode().boundsInRoot
        bounds.set(rect.left.toInt(), rect.top.toInt(), rect.right.toInt(), rect.bottom.toInt())
        return bounds
    }

    private fun assertBackgroundColor(resource: Int, state: String) {
        val context = compose.activity.let { activity ->
            ContextThemeWrapper(activity, 0).apply {
                applyOverrideConfiguration(Configuration(activity.resources.configuration).apply {
                    this.fontScale = fontScale
                    uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                        if (nightMode) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
                })
            }
        }
        val expected = context.getColor(resource)
        val bitmap = compose.onNodeWithTag(ACTION).captureToImage().asAndroidBitmap()
        val colors = linkedSetOf<Int>()
        for (y in 0 until bitmap.height) {
            for (x in 0 until bitmap.width) {
                colors.add(bitmap.getPixel(x, y))
            }
        }
        assertTrue(
            "$state must render application resource ${compose.activity.resources.getResourceName(resource)} " +
                "as ${expected.toHex()}; observed ${colors.map { it.toHex() }}",
            expected in colors,
        )
    }

    private fun capture(name: String): Capture {
        val output = File(outputDirectory(), "native-jvm-theme-$name.png")
        val bitmap = compose.onNodeWithTag(ACTION).captureToImage().asAndroidBitmap()
        FileOutputStream(output).use { stream ->
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream))
        }
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        return Capture(output, pixels)
    }

    private fun outputDirectory(): File {
        val directory = File(requireNotNull(System.getProperty("refract.theme.render.output")))
        check(directory.isDirectory || directory.mkdirs()) { "Cannot create Native JVM theme output directory" }
        return directory
    }

    private data class Capture(val file: File, val pixels: IntArray)

    private companion object {
        const val ACTION = "theme-action"
        const val LABEL = "Appearance and notifications"
    }
}

private fun Int.toHex(): String = String.format("#%08X", this)
