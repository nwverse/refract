package com.example.refract.document

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag

/** Application-owned presentation of content decoded before this boundary. */
@Composable
fun NativeDocumentPreview(
    uri: String,
    displayName: String,
    mimeType: String,
    byteCount: Int,
    revision: Int,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // Do not add URI opening, WebView, decoding, permission or lifecycle work here.
    val decoded = LocalDecodedSyntheticText.current
    if (decoded == null) {
        Text("Preview unavailable: the app has not supplied decoded content.")
        return
    }
    key(uri, revision) {
        Column(modifier = modifier) {
            Text(text = displayName, modifier = Modifier.testTag("document_title"))
            Text(text = "Format: $mimeType; bytes: $byteCount")
            Text(text = decoded.text, modifier = Modifier.testTag("document_body"))
            Button(onClick = onClose, modifier = Modifier.testTag("document_close")) {
                Text("Close document")
            }
            DisposableEffect(revision) {
                decoded.onAppear(revision)
                onDispose { decoded.onDispose(revision) }
            }
        }
    }
}

/** App-provided decoded text; absence is explicit and never creates a fallback fetch. */
val LocalDecodedSyntheticText = androidx.compose.runtime.staticCompositionLocalOf<DecodedSyntheticText?> { null }

data class DecodedSyntheticText(
    val text: String,
    val onAppear: (Int) -> Unit = {},
    val onDispose: (Int) -> Unit = {},
)
