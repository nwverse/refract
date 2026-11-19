package example.app

import android.app.Application
import android.content.res.Configuration
import android.graphics.Color
import org.xmlpull.v1.XmlPullParser
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.v2.AndroidComposeTestRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import com.example.refract.R
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
import refract.generated.TypedAssetScreen

/** Native JVM evidence only: no emulator, device or cross-platform visual comparison. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "notnight", application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class TypedAssetTest {
    @get:Rule
    val compose = AndroidComposeTestRule(
        activityRule = TestRule { base, _ -> base },
        activityProvider = {
            Robolectric.buildActivity(ComponentActivity::class.java)
                .create().start().postCreate(null).resume().visible().windowFocusChanged(true).get()
        },
    )

    @Test
    fun generatedImageUsesLocalizedNativeDescription() {
        compose.setContent { TypedAssetScreen() }
        compose.onNodeWithText("Packaged assets").assertExists()
        compose.onNodeWithText("Synthetic policy fixture", substring = true).assertExists()
        compose.onAllNodes(hasContentDescription("Application logo")).fetchSemanticsNodes().single()
        compose.onNode(hasContentDescription("Application logo"))
            .assertContentDescriptionEquals("Application logo")
    }

    @Test
    @Config(qualifiers = "night")
    fun nightConfigurationSelectsAnotherApplicationDrawable() {
        val application = compose.activity.application
        val lightContext = application.createConfigurationContext(
            Configuration(application.resources.configuration).apply {
                uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or Configuration.UI_MODE_NIGHT_NO
            },
        )
        val nightContext = application.createConfigurationContext(
            Configuration(application.resources.configuration).apply {
                uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or Configuration.UI_MODE_NIGHT_YES
            },
        )
        val light = vectorFillColor(lightContext)
        val dark = vectorFillColor(nightContext)
        assertNotEquals(light, dark)
    }

    @Test
    fun generatedFontResourceScalesWithNativeFontScale() {
        compose.setContent {
            Column {
                CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) { TypedAssetScreen() }
                CompositionLocalProvider(LocalDensity provides Density(2f, 1.5f)) { TypedAssetScreen() }
            }
        }
        val nodes = compose.onAllNodesWithText("Packaged assets").fetchSemanticsNodes()
        assertEquals(2, nodes.size)
        val (normal, large) = nodes.map { textHeight(it) }
        assertTrue("Expected the font resource and sp size to increase with fontScale: $normal -> $large", large > normal)
        // Native font rasterization rounds the resulting line height; it is not a pixel-perfect scale factor.
        assertEquals(normal * 1.5f, large, 3f)
    }

    @Test
    fun rawResourceIsReadOnlyByTheApplicationComponent() {
        val contents = compose.activity.resources.openRawResource(R.raw.privacy_policy)
            .bufferedReader().use { it.readText() }
        assertTrue(contents.contains("\"revision\": 1"))
        compose.setContent { TypedAssetScreen() }
        compose.onNodeWithText("Synthetic policy fixture", substring = true).assertExists()
    }

    private fun textHeight(node: androidx.compose.ui.semantics.SemanticsNode): Float {
        val layouts = node.config.getOrNull(SemanticsActions.GetTextLayoutResult)
        val results = mutableListOf<TextLayoutResult>()
        check(layouts?.action?.invoke(results) == true)
        return results.single().let { it.getLineBottom(0) - it.getLineTop(0) }
    }

    private fun vectorFillColor(context: android.content.Context): Int {
        context.resources.getXml(R.drawable.app_logo).use { parser ->
            while (parser.next() != XmlPullParser.END_DOCUMENT) {
                if (parser.eventType != XmlPullParser.START_TAG || parser.name != "path") continue
                val value = parser.getAttributeValue("http://schemas.android.com/apk/res/android", "fillColor")
                return Color.parseColor(value)
            }
        }
        error("Expected a VectorDrawable path with an application fill color")
    }
}
