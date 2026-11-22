package com.example.refract.input

import android.content.Context
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView

/**
 * Application-owned native editor. Its InputConnection owns Chinese preedit;
 * only committed text enters the shared draft. No generated runtime or IME
 * synthesis is involved.
 */
@Composable
fun NativeTextInputHost(
    draft: String,
    onDraftChange: (String) -> Unit,
    focusRequest: Int,
    onDraftCommit: (String) -> Unit,
    onCommit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val currentDraftChange by rememberUpdatedState(onDraftChange)
    val currentDraftCommit by rememberUpdatedState(onDraftCommit)
    val currentCommit by rememberUpdatedState(onCommit)
    val editorObserver = LocalNativeTextInputHostObserver.current
    val editor = remember {
        NativeDraftEditor(
            onDraftChange = { currentDraftChange(it) },
            onDraftCommit = { currentDraftCommit(it) },
            onCommit = { currentCommit() },
        )
    }

    AndroidView(
        factory = { context ->
            editor.createView(context).also { editorObserver?.invoke(editor) }
        },
        update = { view ->
            // An external parent edit may replace the editor value, but an IME
            // preedit in progress must remain native and uninterrupted.
            if (editor.value.text?.toString() != draft && !editor.hasComposition) {
                editor.replaceCommittedDraft(draft)
            }
        },
        onRelease = { view -> editor.release() },
        modifier = modifier,
    )
    LaunchedEffect(editor, focusRequest) {
        editor.requestFocusFromHost()
    }
}

/** Optional app-owned native test/integration observer; absent from generated signatures. */
val LocalNativeTextInputHostObserver = compositionLocalOf<((NativeDraftEditor) -> Unit)?> { null }

/** Testable native host, independent of Compose's TextField text/value overload. */
class NativeDraftEditor(
    private val onDraftChange: (String) -> Unit,
    private val onDraftCommit: (String) -> Unit,
    private val onCommit: () -> Unit,
) {
    lateinit var value: EditText
        private set

    var hasComposition: Boolean = false
        private set
    private var sendingDraft = false
    private var editorConnection: HostInputConnection? = null

    fun createView(context: Context): EditText {
        check(!::value.isInitialized) { "The native editor belongs to one View instance." }
        value = DraftEditText(context, this)
        value.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        value.imeOptions = EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_EXTRACT_UI
        value.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(text: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(text: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(text: Editable?) {
                // The connection sets this flag synchronously around both
                // setComposingText and commitText; TextWatcher alone cannot
                // reliably distinguish those operations across Android IMEs.
                if (sendingDraft && !hasComposition) {
                    onDraftChange(text?.toString().orEmpty())
                }
            }
        })
        value.setOnFocusChangeListener { _, focused ->
            if (!focused) finishComposing()
        }
        return value
    }

    fun onCreateInputConnection(attributes: EditorInfo): InputConnection {
        attributes.imeOptions = EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_EXTRACT_UI
        attributes.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        attributes.initialSelStart = value.selectionStart
        attributes.initialSelEnd = value.selectionEnd
        return HostInputConnection(value, this).also { editorConnection = it }
    }

    fun requestFocusFromHost() {
        if (!::value.isInitialized) return
        if (value.requestFocus()) {
            value.post {
                if (value.isFocused) {
                    val service = value.context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                    service.showSoftInput(value, InputMethodManager.SHOW_IMPLICIT)
                }
            }
        }
    }

    fun performEditorAction(action: Int): Boolean {
        if (action != EditorInfo.IME_ACTION_DONE) return false
        // Finish the platform preedit first. Do not translate or replace it
        // with a synthetic candidate. Publish only what the native editor
        // contains after its real IME has finished the composition.
        finishComposing()
        val committed = value.text?.toString().orEmpty()
        onDraftCommit(committed)
        value.clearFocus()
        val service = value.context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        service.hideSoftInputFromWindow(value.windowToken, 0)
        onCommit()
        return true
    }

    fun setComposition(composing: Boolean) {
        hasComposition = composing
    }

    fun sendDraft() {
        sendingDraft = true
    }

    fun draftSent() {
        sendingDraft = false
    }

    fun replaceCommittedDraft(draft: String) {
        check(!hasComposition) { "Do not replace a native IME preedit from a String binding." }
        sendingDraft = false
        value.setText(draft)
        value.setSelection(draft.length)
    }

    fun release() {
        if (!::value.isInitialized) return
        finishComposing()
        editorConnection = null
        value.clearFocus()
    }

    private fun finishComposing() {
        if (!::value.isInitialized) return
        val connection = editorConnection
        connection?.finishComposingText()
        hasComposition = false
    }
}

private class DraftEditText(
    context: Context,
    private val host: NativeDraftEditor,
) : EditText(context) {
    override fun onCreateInputConnection(attributes: EditorInfo): InputConnection {
        return host.onCreateInputConnection(attributes)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_ENTER && host.performEditorAction(EditorInfo.IME_ACTION_DONE)) {
            return true
        }
        return super.onKeyDown(keyCode, event)
    }
}

private class HostInputConnection(
    target: View,
    private val host: NativeDraftEditor,
) : BaseInputConnection(target, true) {
    override fun getEditable(): Editable = host.value.text

    override fun setComposingText(text: CharSequence?, newCursorPosition: Int): Boolean {
        host.setComposition(!text.isNullOrEmpty())
        host.sendDraft()
        return try {
            super.setComposingText(text, newCursorPosition)
        } finally {
            host.draftSent()
        }
    }

    override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
        host.setComposition(false)
        host.sendDraft()
        return try {
            super.commitText(text, newCursorPosition)
        } finally {
            host.draftSent()
        }
    }

    override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
        host.sendDraft()
        return try {
            super.deleteSurroundingText(beforeLength, afterLength)
        } finally {
            host.draftSent()
        }
    }

    override fun finishComposingText(): Boolean {
        host.setComposition(false)
        return super.finishComposingText()
    }

    override fun performEditorAction(editorAction: Int): Boolean {
        return host.performEditorAction(editorAction)
    }

    override fun sendKeyEvent(event: KeyEvent?): Boolean {
        // BaseInputConnection sends IME key events back through this View.
        // DraftEditText.onKeyDown owns Enter submission; consuming its matching
        // key-up here would make one IME Enter invoke the commit callbacks twice.
        return super.sendKeyEvent(event)
    }
}
