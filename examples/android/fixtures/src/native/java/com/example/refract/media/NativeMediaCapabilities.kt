package com.example.refract.media

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag

/** App-owned observation only. It is not a player, camera, share sheet or runtime service. */
data class SyntheticMediaObservation(
    val onAppear: (String, Int) -> Unit = { _, _ -> },
    val onDispose: (String, Int) -> Unit = { _, _ -> },
)

/**
 * A static fixture surface. The app owns the real implementation and all system capability checks.
 * This function never reads media, a URI, a permission, a sensor or a recipient.
 */
@Composable
private fun SyntheticCapabilitySurface(
    kind: String,
    identifier: String,
    revision: Int,
    onCancel: () -> Unit,
) {
    key(identifier, revision) {
        val observation = LocalSyntheticMediaObservation.current
        Column(modifier = Modifier.testTag("media_${kind}_ready")) {
            Text(text = "Synthetic $kind surface: $identifier@$revision")
            Button(onClick = onCancel, modifier = Modifier.testTag("media_${kind}_cancel")) {
                Text(text = "Cancel synthetic $kind")
            }
            DisposableEffect(identifier, revision) {
                observation.onAppear(kind, revision)
                onDispose { observation.onDispose(kind, revision) }
            }
        }
    }
}

@Composable
fun NativePlaybackCapability(identifier: String, revision: Int, onCancel: () -> Unit) {
    SyntheticCapabilitySurface("playback", identifier, revision, onCancel)
}

@Composable
fun NativeCameraCapability(identifier: String, revision: Int, onCancel: () -> Unit) {
    SyntheticCapabilitySurface("camera", identifier, revision, onCancel)
}

@Composable
fun NativeShareCapability(identifier: String, revision: Int, onCancel: () -> Unit) {
    SyntheticCapabilitySurface("share", identifier, revision, onCancel)
}

val LocalSyntheticMediaObservation = androidx.compose.runtime.staticCompositionLocalOf {
    SyntheticMediaObservation()
}
