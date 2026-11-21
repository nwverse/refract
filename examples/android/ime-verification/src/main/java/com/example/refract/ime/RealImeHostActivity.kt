package com.example.refract.ime

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.example.refract.input.LocalNativeTextInputHostObserver
import com.example.refract.input.NativeDraftEditor
import refract.generated.ComposerModel
import refract.generated.ComposerScreen

/** Test-owned application state; the generated host owns none of this state. */
internal class RecordingComposerModel : ComposerModel {
    var draft by mutableStateOf("")
    var focusRequest by mutableIntStateOf(0)
    val events = mutableListOf<String>()

    override fun commitDraft(value: String) {
        events += "draft:$value"
        draft = value
    }

    override fun commit() {
        events += "commit"
    }
}

internal object RealImeHostState {
    var model = RecordingComposerModel()
    var editor: NativeDraftEditor? = null
    var hostVisible by mutableStateOf(true)
    var unrelatedRevision by mutableIntStateOf(0)
}

class RealImeHostActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            RealImeVerificationScreen()
        }
    }
}

@Composable
private fun RealImeVerificationScreen() {
    val model = RealImeHostState.model
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Text(
            text = "retained=" + model.draft,
            modifier = Modifier.testTag("retainedDraft"),
        )
        Text(text = "revision=" + RealImeHostState.unrelatedRevision)
        if (RealImeHostState.hostVisible) {
            CompositionLocalProvider(
                LocalNativeTextInputHostObserver provides {
                    RealImeHostState.editor = it
                },
            ) {
                // The exact CLI-staged fixture call, not a reimplementation of
                // ComposerScreen or a second hand-written input host.
                ComposerScreen(
                    draft = model.draft,
                    onDraftChange = { model.draft = it },
                    focusRequest = model.focusRequest,
                    onFocusRequestChange = { model.focusRequest = it },
                    model = model,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("generatedHost"),
                )
            }
        }
        OutlinedTextField(
            value = "",
            onValueChange = {},
            label = { Text("Other field") },
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Text,
                imeAction = ImeAction.None,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .testTag("otherField"),
        )
        Button(
            onClick = { model.focusRequest += 1 },
            modifier = Modifier.testTag("restoreFocus"),
        ) {
            Text("Restore generated focus")
        }
        Button(
            onClick = { RealImeHostState.unrelatedRevision += 1 },
            modifier = Modifier.testTag("recompose"),
        ) {
            Text("Recompose")
        }
        Button(
            onClick = {
                RealImeHostState.editor = null
                RealImeHostState.hostVisible = false
            },
            modifier = Modifier.testTag("removeHost"),
        ) {
            Text("Remove host")
        }
        Button(
            onClick = { RealImeHostState.hostVisible = true },
            modifier = Modifier.testTag("restoreHost"),
        ) {
            Text("Restore host")
        }
    }
}
