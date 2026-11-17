package com.example.refract.themecheck

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.requestFocus
import example.design.ThemedSettingsAction
import java.io.File
import java.io.FileOutputStream
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
 * Native JVM Compose evidence for the actual generated component, not only its resolver.
 *
 * These are Robolectric touch/focus/rendering results, never emulator/device,
 * screen-reader, cross-platform parity or performance evidence.
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

    @Test
    fun actualTouchAndFocusChangeGeneratedPixelsAndDisabledWins() {
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

        // Drive the exact source consumed by the native clickable. A held
        // native press must not outrank disabled, even before cancellation.
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

    private fun render(source: MutableInteractionSource) {
        enabled = true
        compose.setContent {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                ThemedSettingsAction(
                    interactionSource = source,
                    enabled = enabled,
                    onClick = {},
                    modifier = Modifier.testTag(ACTION),
                )
            }
        }
        compose.waitForIdle()
        compose.onNodeWithTag(ACTION).assertIsDisplayed()
    }

    private fun assertBackgroundColor(resource: Int, state: String) {
        val expected = compose.activity.getColor(resource)
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

    private fun capture(name: String) {
        val output = File(outputDirectory(), "native-jvm-theme-$name.png")
        val bitmap = compose.onNodeWithTag(ACTION).captureToImage().asAndroidBitmap()
        FileOutputStream(output).use { stream ->
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream))
        }
        check(output.isFile && output.length() > 1_000) { "Empty Native JVM theme capture: $name" }
    }

    private fun outputDirectory(): File {
        val directory = File(requireNotNull(System.getProperty("refract.theme.render.output")))
        check(directory.isDirectory || directory.mkdirs()) { "Cannot create Native JVM theme output directory" }
        return directory
    }

    private companion object {
        const val ACTION = "theme-action"
    }
}

private fun Int.toHex(): String = String.format("#%08X", this)
