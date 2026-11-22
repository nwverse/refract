package com.example.refract.ime

import android.text.Editable
import android.text.Spanned
import android.view.KeyEvent
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Instrumentation coverage for the native View/InputConnection dispatch path.
 * Deterministic editor operations below are not Chinese-IME evidence.
 */
@RunWith(AndroidJUnit4::class)
class NativeEnterDispatchInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private lateinit var scenario: ActivityScenario<RealImeHostActivity>

    private fun launchFreshGeneratedHost() {
        scenario = ActivityScenario.launch(RealImeHostActivity::class.java)
        assertTrue("The exact generated host must be visible", device.wait(
            Until.hasObject(By.res("com.example.refract.ime", "generatedHost")), 5_000,
        ))
        val initialEditor = attachedEditor()
        instrumentation.runOnMainSync {
            RealImeHostState.hostVisible = false
        }
        assertTrue("The old host must actually leave the window", device.wait(
            Until.gone(By.res("com.example.refract.ime", "generatedHost")), 5_000,
        ))
        instrumentation.runOnMainSync {
            RealImeHostState.hostVisible = true
        }
        assertTrue("A fresh host must enter the window", device.wait(
            Until.hasObject(By.res("com.example.refract.ime", "generatedHost")), 5_000,
        ))
        assertNotSame("Do not reuse editor state across view recreation", initialEditor, attachedEditor())
        device.findObject(By.res("com.example.refract.ime", "generatedHost")).click()
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            assertTrue(attachedEditor().value.isFocused)
        }
    }

    @After
    fun closeHost() {
        if (::scenario.isInitialized) scenario.close()
    }

    @Test
    fun enterDownAndUpFinishCompositionAndSubmitOnce() {
        launchFreshGeneratedHost()

        instrumentation.runOnMainSync {
            val editor = requireAttachedEditor()
            val connection = editor.value.onCreateInputConnection(EditorInfo())

            // Synthetic editor state isolates Enter dispatch from an IME. Do
            // not claim that this creates a candidate or tests a keyboard.
            connection.setComposingText("ni hao", 1)
            assertTrue(editor.hasComposition)
            assertTrue(hasComposingSpan(editor.value.text))
            assertEquals("", RealImeHostState.model.draft)

            // A parent recomposition cannot overwrite the native preedit.
            RealImeHostState.unrelatedRevision += 1
        }
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            val editor = requireAttachedEditor()
            assertEquals("ni hao", editor.value.text.toString())
            assertTrue(hasComposingSpan(editor.value.text))
            assertEquals("", RealImeHostState.model.draft)
            editor.value.onCreateInputConnection(EditorInfo()).commitText("你好", 1)
        }
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            val editor = requireAttachedEditor()
            assertFalse(editor.hasComposition)
            assertEquals("你好", RealImeHostState.model.draft)
            assertEquals(emptyList<String>(), RealImeHostState.model.events)

            // The host connection inherits BaseInputConnection's dispatch of
            // an IME hardware event back to the View. Calling only
            // Instrumentation.sendKeyDownUpSync would bypass this override.
            // No IME action is invoked. The connection hands both events to
            // DraftEditText; its onKeyDown owns the only submission. Send the
            // matching up even if down returns false: discarding it on false
            // would hide the duplicate-submission regression.
            val connection = editor.value.onCreateInputConnection(EditorInfo())
            assertTrue(connection is BaseInputConnection)
            val downDispatched = connection.sendKeyEvent(
                KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER),
            )
            val upDispatched = connection.sendKeyEvent(
                KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER),
            )
            instrumentation.waitForIdleSync()
            assertTrue("The host connection must dispatch Enter down", downDispatched)
            assertTrue("The host connection must dispatch Enter up", upDispatched)
        }
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            // Read after draining native dispatch, including any key event
            // delivered through the attached View's Handler.
            assertEquals(listOf("draft:你好", "commit"), RealImeHostState.model.events)
            assertFalse(requireAttachedEditor().value.isFocused)
        }
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync {
            // A second drained pass must not reveal another key-up callback.
            // The unpatched host submits once on down and again on up.
            assertEquals(listOf("draft:你好", "commit"), RealImeHostState.model.events)
            assertEquals("你好", RealImeHostState.model.draft)
            assertEquals("你好", requireAttachedEditor().value.text.toString())
        }
    }

    private fun requireAttachedEditor() =
        RealImeHostState.editor?.takeIf { it.value.isAttachedToWindow }
            ?: throw AssertionError("The exact generated host is not attached")

    private fun attachedEditor(): com.example.refract.input.NativeDraftEditor {
        lateinit var editor: com.example.refract.input.NativeDraftEditor
        instrumentation.runOnMainSync { editor = requireAttachedEditor() }
        return editor
    }

    private fun hasComposingSpan(text: Editable): Boolean = text
        .getSpans(0, text.length, Any::class.java)
        .any { text.getSpanFlags(it) and Spanned.SPAN_COMPOSING != 0 }
}
