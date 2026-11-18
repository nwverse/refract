package com.example.refract.chat

import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.AndroidComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.printToString
import androidx.compose.ui.test.v2.runAndroidComposeUiTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import refract.generated.ConversationScreen

/** Real CLI-generated Compose and app-owned TextView on Native JVM, not a device or emulator. */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class GeneratedMessageProjectionTest {
    @Test
    fun generatedBlockSurvivesInPlaceContentUpdateAndAppendsInOrder() = runAndroidComposeUiTest<ComponentActivity> {
        val projection = MessageProjection(2, 3)
        projection.create("m1", 1, listOf(ChatBlockFixtures.block("b1", "Hello 汉字"), ChatBlockFixtures.block("b2", "Next")))
        setContent { ConversationScreen(model = projection) }
        onNodeWithText("Hello 汉字").assertTextEquals("Hello 汉字")
        runOnIdle {
            projection.update("m1", 2, ChatBlockFixtures.block("b1", "Updated 🌸"))
            projection.append("m1", 3, listOf(ChatBlockFixtures.block("b3", "Appended")))
            projection.finalize("m1", 4)
            projection.finalize("m1", 4)
        }
        onNodeWithText("Updated 🌸").assertExists()
        onNodeWithText("Next").assertExists()
        onNodeWithText("Appended").assertExists()
        // Each projected block owns the parent's finalized label; all three must remain visible.
        assertEquals(3, onAllNodesWithText("Final").fetchSemanticsNodes().size)
        assertEquals(listOf("b1", "b2", "b3"), projection.snapshot.single().blocks.map { it.id })
        assertEquals(4L, projection.snapshot.single().revision)
    }

    @Test
    fun messageBlocksPreserveTheWholeParentRowIncludingEmptyMessages() = runAndroidComposeUiTest<ComponentActivity> {
        val projection = MessageProjection(3, 2)
        projection.create("m1", 1, listOf(ChatBlockFixtures.block("b1", "A"), ChatBlockFixtures.block("b2", "B")))
        projection.create("empty", 1)
        projection.create("m2", 1, listOf(ChatBlockFixtures.block("b3", "C")))
        setContent { ConversationScreen(model = projection) }
        val orderedText = listOf("m1", "A", "B", "empty", "m2", "C").map { expected ->
            onNodeWithText(expected).fetchSemanticsNode().boundsInRoot.top
        }
        assertTrue(orderedText.zipWithNext().all { (top, next) -> top < next })
        onNodeWithText("empty").assertExists()
        val footers = onAllNodesWithText("Row footer").fetchSemanticsNodes()
        assertEquals(3, footers.size)
        assertTrue(footers.map { it.boundsInRoot.top }.zipWithNext().all { (top, next) -> top < next })
    }

    @Test
    fun nativeTextViewUpdatesWithoutReassigningItsBlockIdentity() {
        val activity = Robolectric.buildActivity(ComponentActivity::class.java).setup().get()
        val block = ChatBlockFixtures.block("b1", "Before 🌸")
        val view = TextView(activity)
        view.tag = block.id
        view.text = block.text
        activity.setContentView(view)
        assertEquals("b1", view.tag)
        assertEquals("Before 🌸", view.text.toString())
        val updated = block.copy(text = "After 汉字")
        view.text = updated.text
        assertEquals("b1", view.tag)
        assertEquals("After 汉字", view.text.toString())
        activity.finish()
    }
}

internal object ChatBlockFixtures {
    fun block(id: String, text: String) = refract.generated.ChatBlock(id = id, text = text)
}
