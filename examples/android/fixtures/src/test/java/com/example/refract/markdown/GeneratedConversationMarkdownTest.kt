package com.example.refract.markdown

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performFirstLinkClick
import androidx.compose.ui.test.v2.runAndroidComposeUiTest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import refract.generated.ConversationModel
import refract.generated.ConversationSnippet

/** Native JVM Compose semantics through the exact staged CLI output, not an emulator or device. */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class GeneratedConversationMarkdownTest {
    @Test
    fun paragraphLinkAndCodeBlockExposeNativeTextAndTypedLinkAction() = runAndroidComposeUiTest<ComponentActivity> {
        val model = RecordingConversationModel()
        setContent { ConversationSnippet(model = model) }

        onNodeWithText("let answer = 42", substring = true).assertIsDisplayed()
        onNodeWithContentDescription("Swift code example").assertIsDisplayed()
        onNodeWithText("func answer() -> Int {\n    return 42\n}\n").assertIsDisplayed()
        onNodeWithText("Here is a", substring = true).assertTextEquals(
            "Here is abounded answerwith an example:let answer = 42Read the documentation"
        ).performFirstLinkClick { range ->
            (range.item as? androidx.compose.ui.text.LinkAnnotation.Url)?.url == "https://example.com/docs"
        }

        assertEquals(listOf("https://example.com/docs"), model.openedLinks)
    }

    private class RecordingConversationModel : ConversationModel {
        val openedLinks = mutableListOf<String>()
        override fun openLink(url: String) {
            openedLinks += url
        }
    }
}
