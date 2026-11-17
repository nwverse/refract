package com.example.refract.input

import android.content.Context
import android.text.Spanned
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.AndroidComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.v2.runAndroidComposeUiTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Native JVM / Robolectric tests of a real EditText and its InputConnection.
 * This is not an emulator, a device, or a third-party Chinese IME test.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NativeTextInputHostTest {
    @Test
    fun generatedHostPreservesChinesePreeditUntilNativeCommit() = runHostTest {
        val recorder = RecordingModel()
        var observedEditor: NativeDraftEditor? by mutableStateOf(null)
        setObservedHost(recorder) { observedEditor = it }
        waitForIdle()
        assertTrue(observedEditor != null)
        val editor = observedEditor ?: run { error("Native editor was not attached") }
        val connection = editor.value.onCreateInputConnection(EditorInfo())

        runOnIdle { connection.setComposingText("ni hao", 1) }
        assertEquals("", recorder.draft)
        assertTrue(editor.hasComposition)
        assertTrue(hasComposingSpan(editor.value.text))

        // An unrelated recomposition must not overwrite the native preedit.
        runOnIdle { recorder.unrelatedRevision++ }
        assertTrue(editor.hasComposition)
        assertEquals("", recorder.draft)

        runOnIdle { connection.commitText("你好", 1) }
        assertEquals("你好", recorder.draft)
        assertEquals(emptyList<String>(), recorder.committedDrafts)
        assertFalse(editor.hasComposition)
    }

    @Test
    fun draftAndSelectionSurviveFocusChange() = runHostTest {
        val recorder = RecordingModel()
        var observedEditor: NativeDraftEditor? by mutableStateOf(null)
        setObservedHost(recorder) { observedEditor = it }
        waitForIdle()
        assertTrue(observedEditor != null)
        val editor = observedEditor ?: run { error("Native editor was not attached") }
        val connection = editor.value.onCreateInputConnection(EditorInfo())
        runOnIdle {
            connection.commitText("草稿🌏", 1)
            editor.value.setSelection(1, 3)
        }
        assertEquals("草稿🌏", recorder.draft)
        assertEquals(1, editor.value.selectionStart)
        assertEquals(3, editor.value.selectionEnd)

        runOnIdle {
            editor.value.clearFocus()
            editor.requestFocusFromHost()
        }
        assertTrue(editor.value.isFocused)
        assertEquals("草稿🌏", recorder.draft)
        assertEquals(1, editor.value.selectionStart)
        assertEquals(3, editor.value.selectionEnd)
    }

    @Test
    fun doneFinishesCompositionThenPublishesActualTextAndDismissesKeyboard() = runHostTest {
        val recorder = RecordingModel()
        var observedEditor: NativeDraftEditor? by mutableStateOf(null)
        setObservedHost(recorder) { observedEditor = it }
        waitForIdle()
        assertTrue(observedEditor != null)
        val editor = observedEditor ?: run { error("Native editor was not attached") }
        editor.requestFocusFromHost()
        val inputMethod = shadowOf(editor.value.context.getSystemService(Context.INPUT_METHOD_SERVICE)
            as InputMethodManager)
        val connection = editor.value.onCreateInputConnection(EditorInfo())
        runOnIdle {
            connection.setComposingText("ni hao", 1)
            connection.commitText("你好", 1)
            connection.setComposingText("ma", 1)
        }
        assertTrue(editor.hasComposition)

        runOnIdle { assertTrue(connection.performEditorAction(EditorInfo.IME_ACTION_DONE)) }
        assertEquals(listOf("你好ma"), recorder.committedDrafts)
        assertEquals(1, recorder.commits)
        assertFalse(editor.hasComposition)
        assertFalse(editor.value.isFocused)
        assertFalse(inputMethod.isSoftInputVisible)
        assertTrue(recorder.draftCommittedBeforeCommit)
    }

    @Test
    fun enterKeyUsesDoneAndIncrementingRequestRestoresFocus() = runHostTest {
        val recorder = RecordingModel()
        var observedEditor: NativeDraftEditor? by mutableStateOf(null)
        setObservedHost(recorder) { observedEditor = it }
        waitForIdle()
        assertTrue(observedEditor != null)
        val editor = observedEditor ?: run { error("Native editor was not attached") }
        val connection = editor.value.onCreateInputConnection(EditorInfo())
        runOnIdle { connection.commitText("你好", 1) }
        editor.value.clearFocus()

        runOnIdle { recorder.focusRequest++ }
        waitForIdle()
        assertTrue(editor.value.isFocused)

        runOnIdle {
            assertTrue(editor.value.onKeyDown(KeyEvent.KEYCODE_ENTER, KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER)))
        }
        assertEquals(listOf("你好"), recorder.committedDrafts)
        assertEquals(1, recorder.commits)
    }

    @Test
    fun externalDraftReplacementDoesNotOverwritePreedit() = runHostTest {
        val recorder = RecordingModel()
        var observedEditor: NativeDraftEditor? by mutableStateOf(null)
        setObservedHost(recorder) { observedEditor = it }
        waitForIdle()
        assertTrue(observedEditor != null)
        val editor = observedEditor ?: run { error("Native editor was not attached") }
        val connection = editor.value.onCreateInputConnection(EditorInfo())
        runOnIdle {
            connection.setComposingText("zhong", 1)
            recorder.draft = "external edit"
        }
        assertEquals("zhong", editor.value.text.toString())
        assertTrue(editor.hasComposition)
        assertEquals("external edit", recorder.draft)

        runOnIdle { connection.commitText("中", 1) }
        assertEquals("中", recorder.draft)
        assertEquals("中", editor.value.text.toString())
    }

    private fun AndroidComposeUiTest<ComponentActivity>.setObservedHost(
        model: RecordingModel,
        observer: (NativeDraftEditor) -> Unit,
    ) {
        setContent {
            CompositionLocalProvider(LocalNativeTextInputHostObserver provides observer) {
                refract.generated.ComposerScreen(
                    draft = model.draft,
                    onDraftChange = { model.draft = it },
                    focusRequest = model.focusRequest,
                    onFocusRequestChange = { model.focusRequest = it },
                    model = model,
                )
            }
        }
    }

    private fun runHostTest(block: AndroidComposeUiTest<ComponentActivity>.() -> Unit) =
        runAndroidComposeUiTest<ComponentActivity>(block = block)

    private class RecordingModel : refract.generated.ComposerModel {
        var draft by mutableStateOf("")
        var focusRequest by mutableIntStateOf(0)
        var unrelatedRevision by mutableIntStateOf(0)
        val committedDrafts = mutableListOf<String>()
        var commits = 0
        var draftCommittedBeforeCommit = false

        override fun commitDraft(value: String) {
            committedDrafts += value
            draft = value
        }

        override fun commit() {
            draftCommittedBeforeCommit = committedDrafts.lastOrNull() == draft
            commits++
        }
    }

    private fun hasComposingSpan(text: CharSequence): Boolean {
        val spanned = text as Spanned
        return spanned.getSpans(0, spanned.length, Any::class.java).any { span ->
            spanned.getSpanFlags(span) and Spanned.SPAN_COMPOSING != 0
        }
    }
}
